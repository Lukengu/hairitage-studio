from django.shortcuts import render
from .models import Post, Category


def blog_details(request):
    id = request.GET.get('id')
    post = Post.objects.get(pk=id)
    categories = Category.objects.raw("""
        SELECT blog_category.id, name, COUNT(blog_post.*) as ct FROM blog_category LEFT JOIN blog_post
        ON blog_category.id = blog_post.category_id_id   GROUP BY blog_category.id ORDER BY blog_category.name
    """)
    return render(request, 'site/blog/details.html', {'post': post, 'categories': categories})