from django.shortcuts import render
from .models import Item, Category
from django.core.paginator import Paginator
from django.db.models import Count, Prefetch
import blog

ITEM_PER_PAGE = 6


def work_page(
        request):
    cat_id = request.GET.get('cat_id')
    if cat_id is None:
        items = Item.objects.all().order_by('-created_at')
    else:
        items = Item.objects.filter(category_id=cat_id).order_by('-created_at')

    paginator = Paginator(items, int(ITEM_PER_PAGE))
    page = request.GET.get('page', 1)
    works = paginator.get_page(page)

    post = blog.models.Post.objects.filter(category_id__name__icontains="Work").filter(status='PUBLISH').first()

    # Get main categories and prefetch their subcategories with item counts
    work_categories = (
        Category.objects
        .filter(parent__isnull=True)  # only top-level categories
        .prefetch_related(
            Prefetch(
                "subcategories",
                queryset=Category.objects.annotate(ct=Count("works")).order_by("name")
            )
        )
        .order_by("name")
    )

    context = {
        'post': post,
        'works': works,
        'range': range(1, works.paginator.num_pages + 1),
        'page': int(page),
        'work_categories': work_categories,
    }
    return render(request, 'site/work.html', context)