from django import template
from ..models import Settings

register = template.Library()


@register.simple_tag
def email_address():
    setting = Settings.objects.filter(pk=1).first()
    return setting.email_address if setting else ""
