from django.db import models
from tinymce.models import HTMLField


class TermsOfService(models.Model):
    content = HTMLField()
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Terms of Service (Updated at: {self.updated_at})"


class PrivacyPolicy(models.Model):
    content = HTMLField()
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Privacy Policy (Updated at: {self.updated_at})"

    class Meta:
        verbose_name_plural = "Privacy Policy"
