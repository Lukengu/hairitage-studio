from django.contrib import admin

from .models import WhatsAppMessage


# Register your models here.
@admin.register(WhatsAppMessage)
class WhatsAppMessageAdmin(admin.ModelAdmin):
    list_display = ['wamid', 'phone_number', 'template_name', 'status', 'error_code', 'error_title','created_at','updated_at']
    list_filter = ['wamid', 'template_name','status']