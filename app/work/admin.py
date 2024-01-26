from django.contrib import admin

from .forms import ServiceForm
from .models import Service, Team


@admin.register(Service)
class ServiceAdmin(admin.ModelAdmin):
    list_display = ['name', 'description']
    list_filter = ['name']
    form = ServiceForm


@admin.register(Team)
class TeamAdmin(admin.ModelAdmin):
    list_display = ['name', 'position', 'intro', 'photo', 'created_at']
    list_filter = ['name']
