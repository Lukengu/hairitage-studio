import os

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = "Reset a Django admin user's password and ensure admin access flags are set."

    def add_arguments(self, parser):
        parser.add_argument(
            "--username",
            default=os.environ.get("DJANGO_SUPERUSER_USERNAME", "admin"),
        )
        parser.add_argument(
            "--email",
            default=os.environ.get("DJANGO_SUPERUSER_EMAIL", ""),
            help="Optional email to set on the user.",
        )
        parser.add_argument(
            "--password",
            default=os.environ.get("DJANGO_SUPERUSER_PASSWORD", ""),
            help="New password (or set DJANGO_SUPERUSER_PASSWORD).",
        )
        parser.add_argument(
            "--create",
            action="store_true",
            help="Create the user when missing instead of failing.",
        )

    def handle(self, *args, **options):
        password = options["password"]
        if not password:
            raise CommandError("Password is required. Set --password or DJANGO_SUPERUSER_PASSWORD.")

        user_model = get_user_model()
        username = options["username"]
        user = user_model.objects.filter(username=username).first()

        if user is None:
            if not options["create"]:
                raise CommandError(f"User {username!r} does not exist.")
            user = user_model(username=username)

        user.set_password(password)
        user.is_staff = True
        user.is_superuser = True
        user.is_active = True
        if options["email"]:
            user.email = options["email"]
        user.save()

        self.stdout.write(self.style.SUCCESS(f"Updated admin user: {username}"))
