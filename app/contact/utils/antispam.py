import logging
import time

import requests
from django.conf import settings
from django.core import signing

logger = logging.getLogger(__name__)

FORM_SIGNING_SALT = "hairitage-contact-form"
MIN_SUBMIT_SECONDS = 3
MAX_SUBMIT_SECONDS = 3600
HONEYPOT_FIELD = "company_website"


class AntispamError(Exception):
    def __init__(self, message, *, silent=False):
        super().__init__(message)
        self.silent = silent


def generate_form_token():
    return signing.dumps({"t": time.time()}, salt=FORM_SIGNING_SALT)


def get_client_ip(request):
    forwarded = request.META.get("HTTP_X_FORWARDED_FOR")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.META.get("REMOTE_ADDR", "")


def verify_honeypot(request):
    if request.POST.get(HONEYPOT_FIELD, "").strip():
        raise AntispamError("honeypot filled", silent=True)


def verify_form_token(token):
    if not token:
        raise AntispamError("missing form token")

    try:
        data = signing.loads(token, salt=FORM_SIGNING_SALT, max_age=MAX_SUBMIT_SECONDS)
    except signing.BadSignature:
        raise AntispamError("invalid form token", silent=True)

    elapsed = time.time() - data["t"]
    if elapsed < MIN_SUBMIT_SECONDS:
        raise AntispamError("submitted too quickly")


def turnstile_enabled():
    return bool(settings.TURNSTILE_SITE_KEY and settings.TURNSTILE_SECRET_KEY)


def verify_turnstile(request):
    if not turnstile_enabled():
        return

    token = request.POST.get("cf-turnstile-response", "").strip()
    if not token:
        raise AntispamError("verification incomplete")

    response = requests.post(
        "https://challenges.cloudflare.com/turnstile/v0/siteverify",
        data={
            "secret": secret_key,
            "response": token,
            "remoteip": get_client_ip(request),
        },
        timeout=10,
    )
    response.raise_for_status()
    if not response.json().get("success"):
        raise AntispamError("verification failed")


def validate_contact_form(request):
    verify_honeypot(request)
    verify_form_token(request.POST.get("form_token"))
    verify_turnstile(request)
