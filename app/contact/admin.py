from django.contrib import admin
from .models import Message, Reply, Appointment


@admin.register(Message)
class MessageAdmin(admin.ModelAdmin):
    list_display = ['subject', 'full_name', 'email', 'subject', 'message_text', 'created_at']
    list_filter = ['subject', 'full_name', 'email', 'created_at']

    def has_add_permission(self, request, obj=None):
        return False

    def has_change_permission(self, request, obj=None):
        return False


@admin.register(Reply)
class ReplyAdmin(admin.ModelAdmin):
    list_display = ['user_id', 'subject', 'message_id', 'subject', 'message_text', 'created_at']
    list_filter = ['subject', 'created_at']


@admin.register(Appointment)
class AppointmentAdmin(admin.ModelAdmin):
    list_display = ['full_name', 'email', 'phone', 'service', 'date', 'time', 'notes', 'created_at']
    list_filter = ['service', 'date', 'created_at']
    search_fields = ['full_name', 'email', 'phone', 'service']
    ordering = ['-created_at']
    readonly_fields = ['created_at']