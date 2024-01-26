from django.shortcuts import render


def settings_page(request):
    context = {}
    return render(request, "admin/settings.html", context)