import random

from django import template
from ..models import Settings

register = template.Library()


@register.simple_tag
def banners():
    banners = ['bg_1.jpg', 'bg_11.jpg', 'bg_13.jpg', 'bg_14.jpg', 'bg_3.jpg']
    index = random.randint(0, len(banners) - 1)
    return banners[index]