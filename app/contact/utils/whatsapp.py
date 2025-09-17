import json

import requests
from django.conf import settings
import logging


from app.log.models import WhatsAppMessage


def send_whatsapp_template(to, template_name, language_code="en", parameters=None):
    """
    Send a WhatsApp template message using Meta's Cloud API.

    Args:
        to (str): Recipient phone number in international format (e.g., '27696867183').
        template_name (str): The approved WhatsApp template name.
        language_code (str): Language code (e.g., 'en', 'en_US').
        parameters (list): List of text strings matching the template placeholders.
    """
    logger = logging.getLogger(__name__)
    headers = {
        "Authorization": f"Bearer {settings.WHATSAPP_ACCESS_TOKEN}",
        "Content-Type": "application/json",
    }

    body = {
        "messaging_product": "whatsapp",
        "to": to,
        "type": "template",
        "template": {
            "name": template_name,
            "language": {"code": language_code},
        },
    }

    if parameters:
        body["template"]["components"] = [
            {
                "type": "body",
                "parameters": [{"type": "text", "text": str(p)} for p in parameters],
            }
        ]

    response = requests.post(settings.WHATSAPP_API_URL, headers=headers, json=body)

    logger.debug("POST %s", settings.WHATSAPP_API_URL)
    logger.debug("Headers: %s", headers)
    logger.debug("Body: %s", json.dumps(body, indent=2))
    logger.debug("Status Code: %s", response.status_code)
    logger.debug("Response: %s", response.text)

    try:
        response.raise_for_status()
    except requests.exceptions.HTTPError as e:
        return {"error": str(e), "details": response.json()}

    data = response.json()
    message_id = data["messages"][0]["id"]
    WhatsAppMessage.objects.create(
        wamid=message_id,
        phone_number=to,
        template_name=template_name,
        status="sent",
    )

    return data