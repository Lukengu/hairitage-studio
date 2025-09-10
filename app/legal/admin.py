from django.contrib import admin
from .models import TermsOfService, PrivacyPolicy


@admin.register(TermsOfService)
class TermsOfServiceAdmin(admin.ModelAdmin):
    list_display = ('updated_at',)


@admin.register(PrivacyPolicy)
class PrivacyPolicyAdmin(admin.ModelAdmin):
    list_display = ('updated_at',)