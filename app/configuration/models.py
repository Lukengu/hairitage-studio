from django.db import models
from tinymce.models import HTMLField


class Settings(models.Model):
    id = models.AutoField(primary_key=True)
    currency_name = models.CharField(max_length=100, null=True, blank=True)
    currency_code = models.CharField(max_length=3, null=True, blank=True)
    physical_address = HTMLField(null=True, blank=True)
    contact_number = models.CharField(max_length=100, null=True, blank=True)
    email_address = models.CharField(max_length=100, null=True, blank=True)
    display_name = models.CharField(max_length=100, null=True, blank=True)
    contact_intro = HTMLField(null=True, blank=True)
    facebook = models.CharField(max_length=100, null=True, blank=True)
    twitter = models.CharField(max_length=100, null=True, blank=True)
    instagram = models.CharField(max_length=100, null=True, blank=True)
    linkedin = models.CharField(max_length=100, null=True, blank=True)
    opening_hours = HTMLField(null=True, blank=True)

    class Meta:
        verbose_name_plural = "settings"


class Stats(models.Model):
    id = models.AutoField(primary_key=True)
    name = models.CharField(max_length=100, null=True)
    count = models.IntegerField()

    class Meta:
        verbose_name_plural = "stats"
