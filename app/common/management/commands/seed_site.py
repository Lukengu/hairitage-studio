import io

from django.contrib.auth.models import User
from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand
from django.db import transaction
from PIL import Image

import blog.models
import configuration.models
import product.models
import work.models


def placeholder_image(name: str, color: tuple[int, int, int]) -> ContentFile:
    image = Image.new("RGB", (800, 600), color)
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=85)
    return ContentFile(buffer.getvalue(), name=name)


class Command(BaseCommand):
    help = "Load starter content for Hairitage Studio (idempotent when --if-empty is set)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--if-empty",
            action="store_true",
            default=True,
            help="Skip seeding when Settings already exists (default).",
        )
        parser.add_argument(
            "--force",
            action="store_true",
            help="Seed even when content already exists.",
        )

    def handle(self, *args, **options):
        if not options["force"] and self._has_existing_content():
            self.stdout.write("Site content already exists. Use --force to re-seed.")
            return

        with transaction.atomic():
            self._seed_settings()
            self._seed_stats()
            self._seed_services()
            self._seed_team()
            self._seed_work()
            user = self._ensure_author()
            self._seed_blog(user)
            self._seed_promotion()

        self.stdout.write(self.style.SUCCESS("Starter site content loaded."))

    def _has_existing_content(self):
        has_settings = configuration.models.Settings.objects.filter(
            display_name__isnull=False,
        ).exclude(display_name="").exists()
        return all([
            has_settings,
            work.models.Service.objects.exists(),
            blog.models.Post.objects.exists(),
        ])

    def _seed_settings(self):
        configuration.models.Settings.objects.update_or_create(
            pk=1,
            defaults={
                "display_name": "Hairitage Studio",
                "currency_name": "Rand",
                "currency_code": "ZAR",
                "physical_address": "<p>Johannesburg, Gauteng<br>South Africa</p>",
                "contact_number": "+27 11 000 0000",
                "email_address": "info@hairitage-studio.co.za",
                "contact_intro": "<p>We would love to hear from you. Book an appointment or send us a message.</p>",
                "facebook": "https://facebook.com/",
                "instagram": "https://instagram.com/",
                "opening_hours": "<p>Mon – Fri: 9:00 – 18:00<br>Sat: 9:00 – 15:00<br>Sun: Closed</p>",
            },
        )

    def _seed_stats(self):
        stats = [
            ("Happy Clients", 1200),
            ("Years of Experience", 10),
            ("Expert Stylists", 6),
            ("Salons Served", 1),
        ]
        for name, count in stats:
            configuration.models.Stats.objects.get_or_create(name=name, defaults={"count": count})

    def _seed_services(self):
        services = [
            (
                "Hair Styling",
                '<span class="flaticon-curl"></span>',
                "Cuts, blow-dry, and styling tailored to your look and lifestyle.",
            ),
            (
                "Colour & Highlights",
                '<span class="flaticon-cosmetics"></span>',
                "Balayage, full colour, and highlights using professional-grade products.",
            ),
            (
                "Treatments",
                '<span class="flaticon-facial-treatment"></span>',
                "Deep conditioning, scalp care, and restorative hair treatments.",
            ),
            (
                "Bridal & Events",
                '<span class="flaticon-flower"></span>',
                "Special-occasion styling for weddings, events, and photo shoots.",
            ),
        ]
        for name, icon, description in services:
            work.models.Service.objects.get_or_create(
                name=name,
                defaults={"icon": icon, "description": description},
            )

    def _seed_team(self):
        members = [
            ("Thandi M.", "Senior Stylist", "Specialist in natural hair care and protective styling.", (120, 90, 70)),
            ("Lerato K.", "Colour Specialist", "Balayage and colour correction with a gentle, precise touch.", (90, 110, 130)),
            ("Nomsa D.", "Salon Manager", "Ensures every guest enjoys a welcoming, premium experience.", (130, 100, 90)),
        ]
        for name, position, intro, color in members:
            team, created = work.models.Team.objects.get_or_create(
                name=name,
                defaults={"position": position, "intro": intro},
            )
            if created or not team.photo:
                team.photo.save(f"{name.lower().replace(' ', '-')}.jpg", placeholder_image(f"{name}.jpg", color), save=True)

    def _seed_work(self):
        categories = [
            ("Braids & Protective Styles", "Beautiful protective styles for everyday wear."),
            ("Colour Work", "Vibrant colour transformations and subtle highlights."),
            ("Cuts & Styling", "Precision cuts and finished styles for any occasion."),
        ]
        for index, (name, description) in enumerate(categories):
            category, created = work.models.Category.objects.get_or_create(
                name=name,
                defaults={"description": description},
            )
            if created or not category.featured_image:
                category.featured_image.save(
                    f"{name.lower().replace(' ', '-')}.jpg",
                    placeholder_image(f"work-{index}.jpg", (150 + index * 20, 100, 120)),
                    save=True,
                )
            if not category.works.exists():
                item = work.models.Item(category=category, title=f"{name} showcase")
                item.image.save(
                    f"item-{index}.jpg",
                    placeholder_image(f"item-{index}.jpg", (110 + index * 25, 80, 90)),
                )
                item.save()

    def _ensure_author(self) -> User:
        user, _ = User.objects.get_or_create(
            username="hairitage",
            defaults={
                "email": "info@hairitage-studio.co.za",
                "is_staff": True,
                "is_active": True,
            },
        )
        return user

    def _seed_blog(self, user: User):
        categories = {
            "Hair Care Tips": "Articles about maintaining healthy hair.",
            "Services": "Details about our salon services.",
            "Our Work": "Portfolio and styling inspiration.",
            "About Hairitage": "Our story and salon philosophy.",
        }
        category_map = {}
        for name, _ in categories.items():
            category, _ = blog.models.Category.objects.get_or_create(name=name)
            category_map[name] = category

        posts = [
            {
                "title": "Welcome to Hairitage Studio",
                "intro": "Your destination for expert hair care in Johannesburg.",
                "content": "<p>We are excited to welcome you to Hairitage Studio. Our team combines skill, creativity, and care to help you look and feel your best.</p>",
                "category": category_map["About Hairitage"],
                "type": "content",
            },
            {
                "title": "Five Tips for Healthy Natural Hair",
                "intro": "Simple habits to keep your hair strong and hydrated.",
                "content": "<p>Moisturise regularly, protect your hair at night, and schedule trims to prevent breakage.</p>",
                "category": category_map["Hair Care Tips"],
                "type": "blog",
            },
            {
                "title": "Why Professional Colour Matters",
                "intro": "Get longer-lasting colour with salon-grade products.",
                "content": "<p>Professional colour services protect your hair while delivering rich, even results.</p>",
                "category": category_map["Hair Care Tips"],
                "type": "blog",
            },
            {
                "title": "Our Signature Services",
                "intro": "Explore cuts, colour, treatments, and event styling.",
                "content": "<p>From everyday styling to special occasions, we offer services for every hair type and texture.</p>",
                "category": category_map["Services"],
                "type": "content",
            },
            {
                "title": "Recent Styles from the Chair",
                "intro": "A look at transformations our stylists are proud of.",
                "content": "<p>Browse our portfolio for inspiration before your next appointment.</p>",
                "category": category_map["Our Work"],
                "type": "content",
            },
        ]

        for index, data in enumerate(posts):
            post, created = blog.models.Post.objects.get_or_create(
                title=data["title"],
                defaults={
                    "intro": data["intro"],
                    "content": data["content"],
                    "status": "PUBLISH",
                    "type": data["type"],
                    "user_id": user,
                    "category_id": data["category"],
                },
            )
            if created or not post.image:
                post.image.save(
                    f"post-{index}.jpg",
                    placeholder_image(f"post-{index}.jpg", (100, 120, 140)),
                )
                post.save()

    def _seed_promotion(self):
        promotion, created = product.models.Promotion.objects.get_or_create(
            title="New Client Welcome Offer",
            defaults={
                "rate": 15,
                "description": "Enjoy 15% off your first visit when you book online.",
                "home_page": True,
            },
        )
        if created or not promotion.banner:
            promotion.banner.save(
                "welcome-offer.jpg",
                placeholder_image("welcome-offer.jpg", (160, 60, 80)),
            )
            promotion.save()
