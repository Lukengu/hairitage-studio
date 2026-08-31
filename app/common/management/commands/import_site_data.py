import json

from django.apps import apps
from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from pathlib import Path


FIXTURE_NAME = "site_content.json"
USER_FIELD_NAMES = ("user_id", "user")


class Command(BaseCommand):
    help = "Load exported site content fixture into the database."

    def add_arguments(self, parser):
        parser.add_argument(
            "--flush",
            action="store_true",
            help="Remove existing site content before loading the fixture.",
        )
        parser.add_argument(
            "--fixture",
            default=FIXTURE_NAME,
            help=f"Fixture filename under app/fixtures/ (default: {FIXTURE_NAME}).",
        )

    def handle(self, *args, **options):
        fixture_path = Path(__file__).resolve().parents[3] / "fixtures" / options["fixture"]
        if not fixture_path.exists():
            self.stderr.write(f"Fixture not found: {fixture_path}")
            self.stderr.write("Run: bash deploy/export-local-data.sh")
            return

        prepared_fixture = self._prepare_fixture(fixture_path)

        try:
            with transaction.atomic():
                if options["flush"]:
                    self._flush_site_content()
                call_command("loaddata", str(prepared_fixture), verbosity=0)
        finally:
            prepared_fixture.unlink(missing_ok=True)

        self.stdout.write(self.style.SUCCESS(f"Loaded fixture: {fixture_path.name}"))

    def _prepare_fixture(self, fixture_path):
        author = self._get_author_user()
        data = json.loads(fixture_path.read_text())
        author_key = [author.username]

        for obj in data:
            fields = obj.get("fields", {})
            for field_name in USER_FIELD_NAMES:
                if field_name in fields:
                    fields[field_name] = author_key

        prepared_path = fixture_path.with_name(f".{fixture_path.stem}.import.json")
        prepared_path.write_text(json.dumps(data, indent=2))
        self.stdout.write(f"  Mapped content authors to user: {author.username}")
        return prepared_path

    def _get_author_user(self):
        user_model = get_user_model()
        author = user_model.objects.filter(username="admin").first()
        if author is None:
            author = user_model.objects.filter(is_superuser=True).order_by("pk").first()
        if author is None:
            raise CommandError(
                "No admin user found in the database. Run deploy/gcp/createsuperuser.sh first."
            )
        return author

    def _flush_site_content(self):
        delete_order = [
            "blog.Comment",
            "blog.Post",
            "blog.Category",
            "work.Item",
            "work.Category",
            "work.Team",
            "work.Service",
            "product.Promotion",
            "configuration.Stats",
            "configuration.Settings",
            "legal.TermsOfService",
            "legal.PrivacyPolicy",
        ]
        for label in delete_order:
            model = apps.get_model(label)
            deleted, _ = model.objects.all().delete()
            if deleted:
                self.stdout.write(f"  Cleared {label}: {deleted}")
