from django.shortcuts import render
from .models import Post, Category
from django.core.paginator import Paginator
ITEM_PER_PAGE = 6


def blog_details(request):
    id = request.GET.get('id')
    post = Post.objects.get(pk=id)
    categories = Category.objects.raw("""
        SELECT blog_category.id, name, COUNT(blog_post.*) as ct FROM blog_category LEFT JOIN blog_post
        ON blog_category.id = blog_post.category_id_id WHERE blog_post.type = 'blog'   GROUP BY blog_category.id ORDER BY blog_category.name
    """)
    return render(request, 'site/blog/details.html', {'post': post, 'categories': categories})


def blog_page(request):
    cat_id = request.GET.get('cat_id')
    if cat_id is None:
        blogs = Post.objects.filter(type='blog').filter(status='PUBLISH').all().order_by("-date")
    else:
        blogs = Post.objects.filter(type='blog').filter(status='PUBLISH').filter(category_id=cat_id).all().order_by("-date")
    paginator = Paginator(blogs, int(ITEM_PER_PAGE))
    page = request.GET.get('page', 1)
    posts = paginator.get_page(page)

    context = {'posts': posts, 'range': range(1, posts.paginator.num_pages + 1), 'page': int(page)}
    return render(request, 'site/posts.html', context)


def about_page(request):
    context = {'content': Post.objects.filter(type='content').filter(status='PUBLISH').filter(category_id__name__icontains="Hair").first()}
    return render(request, 'site/about.html', context)