import json
import logging
from django.http import HttpResponse
from django.views.decorators.csrf import csrf_exempt
from .models import WhatsAppMessage

logger = logging.getLogger(__name__)

VERIFY_TOKEN = "7YGBhywTr34p09-Lt"  # Replace with your actual verify token

# Create your views here.
@csrf_exempt
def whatsapp_webhook(request):
    if request.method == "GET":
        verify_token = request.GET.get("hub.verify_token")
        challenge = request.GET.get("hub.challenge")
        if verify_token == VERIFY_TOKEN:
            return HttpResponse(challenge, status=200)
        return HttpResponse("Verification failed", status=403)

    elif request.method == "POST":
        try:
            body = json.loads(request.body.decode("utf-8"))
            for entry in body.get("entry", []):
                for change in entry.get("changes", []):
                    value = change.get("value", {})
                    statuses = value.get("statuses", [])

                    for status in statuses:
                        wamid = status.get("id")  # message id
                        status_value = status.get("status")

                        errors = status.get("errors", [])
                        error_code = errors[0]["code"] if errors else None
                        error_title = errors[0]["title"] if errors else None

                        # ✅ Update the existing message instead of creating a new one
                        WhatsAppMessage.objects.filter(wamid=wamid).update(
                            status=status_value,
                            error_code=error_code,
                            error_title=error_title,
                        )
        except Exception as e:
            logger.error("Webhook error: %s", e)
            return HttpResponse("Invalid payload", status=400)

        return HttpResponse("EVENT_RECEIVED", status=200)
    return None