from django.contrib import admin
from .models import Promotion


@admin.register(Promotion)
class PromotionAdmin(admin.ModelAdmin):
    list_display = ['title', 'rate', 'description', 'home_page']
    list_filter = ['title', 'rate', 'home_page']