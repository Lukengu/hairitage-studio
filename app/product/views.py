from .models import Promotion
from blog.models import Post
from django.shortcuts import render
import product
import configuration


def service_page(request):
    promotion = Promotion.objects.filter(home_page=True).order_by('-created_at').first()
    post = Post.objects.filter(category_id__name__icontains="Service").filter(status='PUBLISH').first()
    context = {
        'promotion': promotion,
        'stats': configuration.models.Stats.objects.all(),
        'post': post
    }
    return render(request, 'site/services.html', context)