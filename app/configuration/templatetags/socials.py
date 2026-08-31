from django import template
from ..models import Settings

register = template.Library()


@register.inclusion_tag('site/tags/socials.html', takes_context=True)
def socials(context):
    setting = Settings.objects.filter(pk=1).first()
    return {
        'facebook': setting.facebook if setting else '',
        'twitter': setting.twitter if setting else '',
        'instagram': setting.instagram if setting else '',
        'linkedin': setting.linkedin if setting else '',
        'tiktok': setting.tiktok if setting else '',
    }