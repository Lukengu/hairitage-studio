from django.contrib import admin
from .models import Settings, Stats


@admin.register(Settings)
class SettingsAdmin(admin.ModelAdmin):
    list_display = ['display_name', 'email_address', 'physical_address', 'contact_number',
                    'currency_code', 'currency_name', 'facebook', 'twitter', 'instagram', 'linkedin', 'tiktok', 'opening_hours']


@admin.register(Stats)
class StatsAdmin(admin.ModelAdmin):
    list_display = ['name', 'count']
