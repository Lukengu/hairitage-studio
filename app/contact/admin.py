from django.contrib import admin
from .models import Message, Reply


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