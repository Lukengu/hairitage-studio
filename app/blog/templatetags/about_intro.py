from django import template
from ..models import Post

register = template.Library()


@register.simple_tag
def about_intro():
    content = Post.objects.filter(type='content').filter(status='PUBLISH').first()
    return content.intro
