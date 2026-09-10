from django.shortcuts import render

import configuration.models

from .models import PriceCategory


def pricing_page(request):
    setting = configuration.models.Settings.objects.filter(pk=1).first()
    context = {
        'price_categories': PriceCategory.objects.prefetch_related('items').all(),
        'currency_code': setting.currency_code if setting else 'ZAR',
    }
    return render(request, 'site/pricing.html', context)
