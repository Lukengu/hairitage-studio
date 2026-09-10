from django import template

from ..models import FAQ

register = template.Library()


@register.inclusion_tag('site/tags/faqs.html', takes_context=True)
def faqs(context):
    return {
        'faqs': FAQ.objects.filter(is_active=True),
    }
