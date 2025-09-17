from django.db import models

# Create your models here.
class WhatsAppMessage(models.Model):
    wamid = models.CharField(max_length=255, unique=True)  # message_id from Meta
    phone_number = models.CharField(max_length=20)
    template_name = models.CharField(max_length=100, blank=True)
    status = models.CharField(max_length=50, default="sent")  # sent, delivered, read, failed
    error_code = models.CharField(max_length=50, blank=True)
    error_title = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.phone_number} - {self.status}"