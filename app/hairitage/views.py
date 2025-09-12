from django.shortcuts import render, redirect
from django.core.paginator import Paginator
from django.contrib import messages
from django import template
from django.core.mail import EmailMessage, get_connection
from django.conf import settings
from django.db.models import Count
from django.template.loader import render_to_string


import product
import configuration
import contact
import blog
import work

register = template.Library()


def home_page(request):
    promotion = product.models.Promotion.objects.filter(home_page=True).order_by('-created_at').first()
    posts = blog.models.Post.objects.filter(type='blog').filter(status='PUBLISH').order_by('-date')[:3:1]
    work_categories = work.models.Category.objects.filter(parent_id__isnull=True).order_by('name')

    context = {
        'services': work.models.Service.objects.all().order_by('name'),
        'promotion': promotion,
        'posts': posts,
        'stats': configuration.models.Stats.objects.all(),
        'work_categories': work_categories
    }

    return render(request, "site/home.html", context)