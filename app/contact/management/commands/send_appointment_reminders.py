import logging
from datetime import datetime, timedelta

from django.core.management.base import BaseCommand
from django.template.loader import render_to_string
from django.utils import timezone

from contact.models import Appointment
from contact.utils.email import send_email
from contact.utils.whatsapp import send_whatsapp_template

logger = logging.getLogger(__name__)


def _appointment_datetime(appt):
    return timezone.make_aware(
        datetime.combine(appt.date, appt.time),
        timezone.get_current_timezone(),
    )


class Command(BaseCommand):
    help = "Send WhatsApp and email reminders for upcoming appointments."

    def handle(self, *args, **options):
        now = timezone.localtime()

        window_30_from = now + timedelta(minutes=25)
        window_30_to = now + timedelta(minutes=35)
        window_5_from = now + timedelta(minutes=2)
        window_5_to = now + timedelta(minutes=8)

        dates = {
            window_30_from.date(),
            window_30_to.date(),
            window_5_from.date(),
            window_5_to.date(),
        }

        candidates = Appointment.objects.filter(
            date__in=dates,
        ).exclude(reminder_30_sent=True, reminder_5_sent=True)

        sent_count = 0

        for appt in candidates:
            appt_dt = _appointment_datetime(appt)

            if not appt.reminder_30_sent and window_30_from <= appt_dt <= window_30_to:
                self._send_reminder(appt, minutes=30)
                appt.reminder_30_sent = True
                appt.save(update_fields=["reminder_30_sent"])
                sent_count += 1

            if not appt.reminder_5_sent and window_5_from <= appt_dt <= window_5_to:
                self._send_reminder(appt, minutes=5)
                appt.reminder_5_sent = True
                appt.save(update_fields=["reminder_5_sent"])
                sent_count += 1

        self.stdout.write(f"Reminders sent: {sent_count}")

    def _send_reminder(self, appt, minutes):
        label = f"{minutes} minutes"
        try:
            send_email(
                subject=f"Reminder: Your appointment is in {label}",
                message=render_to_string(
                    "site/emails/appointment_reminder.html",
                    {
                        "full_name": appt.full_name,
                        "service": appt.service,
                        "date": appt.date,
                        "time": appt.time,
                        "minutes": minutes,
                    },
                ),
                recipient_list=[appt.email],
            )
        except Exception:
            logger.exception(
                "Failed to send %s reminder email to %s", label, appt.email
            )

        try:
            send_whatsapp_template(
                to=appt.phone.lstrip("+"),
                template_name="mm_appointment_reminder",
                language_code="en",
                parameters=[appt.full_name, appt.service, str(appt.date), str(appt.time), label],
            )
        except Exception:
            logger.exception(
                "Failed to send %s reminder WhatsApp to %s", label, appt.phone
            )
