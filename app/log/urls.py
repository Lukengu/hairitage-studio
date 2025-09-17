from django.urls import path

from .log.views import whatsapp_webhook

urlpatterns = [
    path('whatsapp/webhook', whatsapp_webhook, name="whatsapp_webhook")
]