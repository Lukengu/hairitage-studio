from django import template
from ..models import Post
from django.utils.safestring import mark_safe
register = template.Library()


@register.simple_tag
def about_intro():
    content = Post.objects.filter(type='content').filter(status='PUBLISH').first()
    return mark_safe(content.intro)
