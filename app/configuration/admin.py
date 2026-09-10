from django.contrib import admin
from .models import Settings, Stats, FAQ


@admin.register(Settings)
class SettingsAdmin(admin.ModelAdmin):
    list_display = ['display_name', 'email_address', 'physical_address', 'contact_number',
                    'currency_code', 'currency_name', 'facebook', 'twitter', 'instagram', 'linkedin', 'tiktok', 'opening_hours']


@admin.register(Stats)
class StatsAdmin(admin.ModelAdmin):
    list_display = ['name', 'count']


@admin.register(FAQ)
class FAQAdmin(admin.ModelAdmin):
    list_display = ['question', 'order', 'is_active']
    list_editable = ['order', 'is_active']
    search_fields = ['question', 'answer']
    ordering = ['order', 'id']
