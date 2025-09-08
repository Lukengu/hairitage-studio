from django.contrib import admin

from .forms import ServiceForm
from .models import Service, Team, Category, Item


@admin.register(Service)
class ServiceAdmin(admin.ModelAdmin):
    list_display = ['name', 'description']
    list_filter = ['name']
    form = ServiceForm


@admin.register(Team)
class TeamAdmin(admin.ModelAdmin):
    list_display = ['name', 'position', 'intro', 'photo', 'created_at']
    list_filter = ['name']


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ['name', 'description', 'parent', 'created_at', 'updated_at']
    list_filter = ['name', 'parent']
    search_fields = ['name', 'description']
    ordering = ['name', 'created_at']
    readonly_fields = ['created_at', 'updated_at']


@admin.register(Item)
class ItemAdmin(admin.ModelAdmin):
    list_display = ['title', 'category', 'image', 'created_at']
    list_filter = ['category']
    search_fields = ['title', 'description']
    ordering = ['created_at']
    readonly_fields = ['created_at', 'updated_at']