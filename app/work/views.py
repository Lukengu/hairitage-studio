from django.shortcuts import render
from .models import Item, Category
from django.core.paginator import Paginator
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
        .filter(parent_id__isnull=True)
        .prefetch_related('subcategories')
        .order_by('name')
    )

    subcategories = Category.objects.raw(
        """
        SELECT
            work_category.id,
            work_category.name,
            COUNT(work.*) as ct
        FROM work_category
        LEFT JOIN work
            ON work_category.id = work.category_id
        WHERE work_category.parent_id IS NOT NULL
        GROUP BY work.category_id
        ORDER BY work_category.name
        """
    )

    context = {
        'post': post,
        'works': works,
        'range': range(1, works.paginator.num_pages + 1),
        'page': int(page),
        'work_categories': work_categories,
        'subcategories': subcategories,
    }
    return render(request, 'site/work.html', context)