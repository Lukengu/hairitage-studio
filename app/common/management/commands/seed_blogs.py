import json
from datetime import date, timedelta
from pathlib import Path

import requests
from django.contrib.auth import get_user_model
from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

import blog.models

FIXTURE_NAME = "blog_posts_seed.json"
PEXELS_IMAGE_URL = "https://images.pexels.com/photos/{photo_id}/pexels-photo-{photo_id}.jpeg"


FALLBACK_PEXELS_IDS = (
    3993444, 5128012, 7755236, 19348319, 3997983, 3025109, 4374426, 8980193,
)


class Command(BaseCommand):
    help = "Create blog posts with downloaded Pexels cover images (skips existing titles)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--fixture",
            default=FIXTURE_NAME,
            help=f"JSON file under app/fixtures/ (default: {FIXTURE_NAME}).",
        )
        parser.add_argument(
            "--limit",
            type=int,
            default=0,
            help="Maximum number of posts to create (0 = all in fixture).",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Print actions without writing to the database.",
        )

        parser.add_argument(
            "--refresh-images",
            action="store_true",
            help="Re-download cover images for posts that already exist.",
        )

        parser.add_argument(
            "--titles",
            nargs="*",
            help="Only process posts with these exact titles.",
        )

    def handle(self, *args, **options):
        fixture_path = Path(__file__).resolve().parents[3] / "fixtures" / options["fixture"]
        if not fixture_path.exists():
            raise CommandError(f"Fixture not found: {fixture_path}")

        posts = json.loads(fixture_path.read_text())
        if options["limit"]:
            posts = posts[: options["limit"]]

        author = self._get_author()
        created = 0
        skipped = 0
        updated = 0

        title_filter = options.get("titles") or None

        for index, entry in enumerate(posts):
            title = entry["title"]
            if title_filter and title not in title_filter:
                continue
            existing = blog.models.Post.objects.filter(title=title).first()

            if existing and options["refresh_images"]:
                if options["dry_run"]:
                    self.stdout.write(f"  Would refresh image: {title}")
                    updated += 1
                    continue
                with transaction.atomic():
                    self._attach_image(existing, entry["pexels_id"])
                    existing.save(update_fields=["image"])
                updated += 1
                self.stdout.write(self.style.SUCCESS(f"  Refreshed image: {title}"))
                continue

            if existing:
                self.stdout.write(f"  Skip (exists): {title}")
                skipped += 1
                continue

            if options["dry_run"]:
                self.stdout.write(f"  Would create: {title}")
                created += 1
                continue

            with transaction.atomic():
                post = self._create_post(entry, author, index)
                self._attach_image(post, entry["pexels_id"])
                post.save()
                created += 1
                self.stdout.write(self.style.SUCCESS(f"  Created: {title}"))

        self.stdout.write(
            self.style.SUCCESS(
                f"Done. Created {created}, updated {updated}, skipped {skipped}."
            )
        )

    def _get_author(self):
        user_model = get_user_model()
        author = user_model.objects.filter(username="admin").first()
        if author is None:
            author = user_model.objects.filter(username="sysadmin").first()
        if author is None:
            author = user_model.objects.filter(is_superuser=True).order_by("pk").first()
        if author is None:
            raise CommandError(
                "No admin user found. Run deploy/gcp/createsuperuser.sh first."
            )
        return author

    def _create_post(self, entry, author, index):
        paragraphs = entry.get("paragraphs", [])
        body = "".join(f"<p>{paragraph}</p>" for paragraph in paragraphs)
        category = blog.models.Category.objects.filter(pk=entry["category_id"]).first()
        if category is None:
            raise CommandError(f"Unknown category_id: {entry['category_id']}")

        publish_date = date.today() - timedelta(days=index * 3)
        return blog.models.Post(
            title=entry["title"][:100],
            intro=entry["intro"],
            content=body,
            status="PUBLISH",
            type="blog",
            user_id=author,
            category_id=category,
            date=publish_date,
        )

    def _attach_image(self, post, photo_id):
        content = self._download_pexels_image(photo_id)
        if content is None:
            for fallback_id in FALLBACK_PEXELS_IDS:
                content = self._download_pexels_image(fallback_id)
                if content is not None:
                    photo_id = fallback_id
                    self.stderr.write(f"  Using fallback image {fallback_id} for {post.title}")
                    break
        if content is None:
            raise CommandError(f"Could not download image for: {post.title}")

        filename = f"pexels-{photo_id}.jpg"
        post.image.save(filename, ContentFile(content), save=False)

    def _download_pexels_image(self, photo_id):
        try:
            response = requests.get(
                PEXELS_IMAGE_URL.format(photo_id=photo_id),
                params={"auto": "compress", "cs": "tinysrgb", "w": "1200"},
                timeout=60,
                headers={"User-Agent": "HairitageStudio/1.0"},
            )
            response.raise_for_status()
            return response.content
        except requests.RequestException as exc:
            self.stderr.write(f"  Image download failed for {photo_id}: {exc}")
            return None
