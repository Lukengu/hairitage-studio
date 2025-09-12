from django import template
from ..models import Settings

register = template.Library()


@register.inclusion_tag('site/tags/socials.html', takes_context=True)
def socials(context):
    setting = Settings.objects.get(pk=1)
    return {
        'facebook': setting.facebook,
        'twitter': setting.twitter,
        'instagram': setting.instagram,
        'linkedin': setting.linkedin,
    }