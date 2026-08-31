import logging

from .utils.antispam import AntispamError, generate_form_token, turnstile_enabled, validate_contact_form
from .utils.whatsapp import send_whatsapp_template
from .utils.email import send_email
from .models import Appointment, Prospect, Message
from django.conf import settings
from django.contrib import messages
from django.core.mail import EmailMessage, get_connection
from django.shortcuts import render, redirect
from django.template.loader import render_to_string
from django.utils.html import strip_tags
import work
import configuration

logger = logging.getLogger(__name__)


def _map_context():
    site = configuration.models.Settings.objects.first()
    address = ""
    if site and site.physical_address:
        address = strip_tags(site.physical_address).strip()
    lat = -26.1366667
    lng = 28.1511111
    return {
        "map_address": address,
        "map_lat": lat,
        "map_lng": lng,
        "map_title": site.display_name if site else "Hairitage Studio",
    }


def _contact_form_context():
    return {
        "form_token": generate_form_token(),
        "turnstile_site_key": settings.TURNSTILE_SITE_KEY,
        "turnstile_enabled": turnstile_enabled(),
    }


def _block_spam_submission(request, exc):
    logger.warning("Antispam blocked submission: %s", exc)
    if exc.silent:
        return redirect("contact")
    if "verification" in str(exc).lower():
        messages.error(request, "Please complete the Cloudflare verification and try again.")
    else:
        messages.error(request, "Could not submit the form. Please wait a few seconds and try again.")
    return redirect("contact")


def book_appointment(request):
    if request.method == 'POST':
        try:
            validate_contact_form(request)
        except AntispamError as exc:
            return _block_spam_submission(request, exc)

        full_name = request.POST.get('full_name')
        email = request.POST.get('email')

        service = request.POST.get('service')
        date = request.POST.get('appointment_date')
        time = request.POST.get('appointment_time')
        notes = request.POST.get('notes')
        phone = request.POST.get('phone')
        site = configuration.models.Settings.objects.first()
        site_name = site.display_name if site else "Hairitage Studio"
        # Save the appointment
        appointment = Appointment(full_name=full_name, email=email, phone=phone, service=service, date=date, time=time, notes=notes)
        appointment.save()
        prospect = Prospect(full_name=full_name, email=email, phone=phone)
        prospect.save()
        # Build message for logs
        message_text = (
            f"Appointment for {full_name} ({email}, {phone})\n"
            f"Service: {service}\n"
            f"Date: {date} at {time}\n"
            f"Notes: {notes}"
        )

        message = Message(
            full_name=site_name,
            email=settings.DEFAULT_FROM_EMAIL,
            message_text=message_text,
            subject="New Appointment"
        )
        message.save()

        try:
            send_email(
                subject=f"Your Appointment Confirmation – {site_name}",
                message=render_to_string(
                    "site/emails/appointment_acknowledgment.html",
                    {"full_name": full_name, "service": service, "date": date, "time": time},
                ),
                recipient_list=[email],
            )
        except Exception:
            logger.exception("Failed to send appointment acknowledgment email to %s", email)

        try:
            send_whatsapp_template(
                to=phone.lstrip("+"),
                template_name="booking_confirmed",
                language_code="en",
                parameters=[full_name, service, date, time],
            )
        except Exception:
            logger.exception("Failed to send appointment WhatsApp confirmation to %s", phone)

        try:
            send_email(
                subject=f"New Appointment: {full_name} - {service}",
                message=render_to_string(
                    "site/emails/appointment_admin.html",
                    {
                        "full_name": full_name,
                        "email": email,
                        "phone": phone,
                        "service": service,
                        "date": date,
                        "time": time,
                        "notes": notes,
                    },
                ),
                recipient_list=[settings.DEFAULT_FROM_EMAIL],
            )
        except Exception:
            logger.exception("Failed to send appointment admin email")

        try:
            send_whatsapp_template(
                to="27843939484",
                template_name="booking_admin",
                language_code="en",
                parameters=[full_name, service, email, phone, date, time, notes or "No additional notes."],
            )
        except Exception:
            logger.exception("Failed to send appointment admin WhatsApp notification")

        messages.success(
            request,
            'Your appointment has been successfully received. We’ve sent you a confirmation email.',
        )
        return redirect('contact')
    return redirect('contact')


def contact_page(request):
    if request.method == 'POST':
        try:
            validate_contact_form(request)
        except AntispamError as exc:
            return _block_spam_submission(request, exc)

        full_name = request.POST.get('full_name')
        email = request.POST.get('email')
        message_text = request.POST.get('message_text')
        subject = request.POST.get('subject')

        message = Message(full_name=full_name, email=email, message_text=message_text, subject=subject)
        message.save()

        try:
            send_email_with(message)
        except Exception:
            logger.exception("Failed to send contact form emails for %s", email)

        messages.success(request, 'Your message has been successfully received.')
        return redirect('contact.html')

    services = work.models.Service.objects.all().order_by('name')

    return render(request, 'site/contact.html', {
        'services': services,
        **_contact_form_context(),
        **_map_context(),
    })


def send_email_with(message):
    site = configuration.models.Settings.objects.first()
    with get_connection(
            host=settings.EMAIL_HOST,
            port=settings.EMAIL_PORT,
            username=settings.EMAIL_HOST_USER,
            password=settings.EMAIL_HOST_PASSWORD,
            use_tls=settings.EMAIL_USE_TLS,
            use_ssl=settings.EMAIL_USE_SSL,
    ) as connection:
        # --- Acknowledgement to the user ---
        user_subject = f"Thanks for contacting {site.display_name}"
        user_body = render_to_string("site/emails/contact_acknowledgment.html", {
            "full_name": message.full_name,
            "subject": message.subject,
        })

        ack_email = EmailMessage(
            subject=user_subject,
            body=user_body,
            from_email=settings.DEFAULT_NO_REPLY_EMAIL,
            to=[message.email],
            reply_to=[settings.DEFAULT_FROM_EMAIL],
            connection=connection,
        )
        ack_email.content_subtype = "html"
        ack_email.send()

        # --- Notification to system/admin ---
        admin_subject = f"New Inquiry: {message.subject}"
        admin_body = render_to_string("site/emails/contact_admin.html", {
            "full_name": message.full_name,
            "email": message.email,
            "subject": message.subject,
            "message_text": message.message_text,
        })

        admin_email = EmailMessage(
            subject=admin_subject,
            body=admin_body,
            from_email=settings.DEFAULT_NO_REPLY_EMAIL,
            to=[settings.DEFAULT_FROM_EMAIL],
            reply_to=[message.email],
            connection=connection,
        )
        admin_email.content_subtype = "html"
        admin_email.send()