from django.conf import settings
from django.core.mail import get_connection, EmailMessage


def send_email(subject, message, recipient_list, from_email=settings.DEFAULT_FROM_EMAIL):
    """
    Send an email using Django's email backend.

    Args:
        subject (str): Subject of the email.
        message (str): Body of the email.
        recipient_list (list): List of recipient email addresses.
        from_email (str): Sender's email address.
    """
    with get_connection(host=settings.EMAIL_HOST, port=settings.EMAIL_PORT, username=settings.EMAIL_HOST_USER, password=settings.EMAIL_HOST_PASSWORD,
                         use_tls=settings.EMAIL_USE_TLS) as connection:
        user_email = EmailMessage(subject=subject, body=message, from_email=from_email, to=recipient_list, reply_to=[settings.DEFAULT_FROM_EMAIL], connection=connection)
        user_email.content_subtype = "html"
        user_email.send()