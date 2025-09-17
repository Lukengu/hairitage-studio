from .utils.whatsapp import send_whatsapp_template
from .utils.email import send_email
from .models import Appointment, Prospect, Message
from django.conf import settings
from django.core.mail import EmailMessage, get_connection
from django.contrib import messages
from django.shortcuts import render, redirect
from django.template.loader import render_to_string
import phonenumbers
import work
import configuration



class PhoneNumberField:
    pass


def book_appointment(request):
    if request.method == 'POST':
        full_name = request.POST.get('full_name')
        email = request.POST.get('email')

        service = request.POST.get('service')
        date = request.POST.get('appointment_date')
        time = request.POST.get('appointment_time')
        notes = request.POST.get('notes')
        phone = request.POST.get('phone')
        site = configuration.models.Settings.objects.first()
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
            full_name=site.display_name,
            email=settings.DEFAULT_FROM_EMAIL,
            message_text=message_text,
            subject="New Appointment"
        )
        message.save()

        send_email(subject=f"Your Appointment Confirmation – {site.display_name}", message = render_to_string("site/emails/appointment_acknowledgment.html",
                                                                                                             {"full_name": full_name, "service": service, "date": date, "time": time}), recipient_list = [email])
        send_whatsapp_template(to = phone.lstrip("+"), template_name="booking_confirmed", language_code="en", parameters=[full_name, service, date, time])

        send_email(
            subject = f"New Appointment: {full_name} - {service}", message = render_to_string("site/emails/appointment_admin.html", {"full_name": full_name, "email": email,
                                                                                                                                    "phone": phone, "service": service, "date": date, "time": time, "notes": notes, }), recipient_list = [settings.DEFAULT_FROM_EMAIL])
        send_whatsapp_template(
            to="27843939484",
            template_name="booking_admin",
            language_code="en",
            parameters=[full_name, service, email, phone, date, time, notes or "No additional notes."]
        )

        messages.success(request, 'Your appointment has been successfully received. We’ve sent you a confirmation email.')

        return render(request, 'site/contact.html', {
            'services': work.models.Service.objects.all().order_by('name')
        })
    return None


def contact_page(request):
    if request.method == 'POST':
        full_name = request.POST.get('full_name')
        email = request.POST.get('email')
        message_text = request.POST.get('message_text')
        subject = request.POST.get('subject')

        message = Message(full_name=full_name, email=email, message_text=message_text, subject=subject)
        message.save()

        send_email_with(message)
        messages.success(request, 'Your message has been successfully received.')
        return redirect('contact.html')

    services = work.models.Service.objects.all().order_by('name')

    return render(request, 'site/contact.html', {'services': services})


def send_email_with(message):
    site = configuration.models.Settings.objects.first()
    with get_connection(
            host=settings.EMAIL_HOST,
            port=settings.EMAIL_PORT,
            username=settings.EMAIL_HOST_USER,
            password=settings.EMAIL_HOST_PASSWORD,
            use_tls=settings.EMAIL_USE_TLS
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