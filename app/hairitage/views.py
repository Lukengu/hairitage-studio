from django.shortcuts import render, redirect
from django.core.paginator import Paginator
from django.contrib import messages
from django import template
from django.core.mail import EmailMessage, get_connection
from django.conf import settings
from django.db.models import Count
from django.template.loader import render_to_string

import work
import product
import blog
import configuration
import contact

register = template.Library()
ITEM_PER_PAGE = 6


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


def about_page(request):
    context = {'content': blog.models.Post.objects.filter(type='content').filter(status='PUBLISH').all().first()}
    return render(request, 'site/about.html', context)


def blog_page(request):
    cat_id = request.GET.get('cat_id')
    if cat_id is None:
        blogs = blog.models.Post.objects.filter(type='blog').filter(status='PUBLISH').all().order_by("-date")
    else:
        blogs = blog.models.Post.objects.filter(type='blog').filter(status='PUBLISH').filter(category_id=cat_id).all().order_by("-date")
    paginator = Paginator(blogs, int(ITEM_PER_PAGE))
    page = request.GET.get('page', 1)
    posts = paginator.get_page(page)

    context = {'posts': posts, 'range': range(1, posts.paginator.num_pages + 1), 'page': int(page)}
    return render(request, 'site/posts.html', context)


def book_appointment(request):
    if request.method == 'POST':
        full_name = request.POST.get('full_name')
        email = request.POST.get('email')
        phone = request.POST.get('phone')
        service = request.POST.get('service')
        date = request.POST.get('appointment_date')
        time = request.POST.get('appointment_time')
        notes = request.POST.get('notes')

        # Save the appointment
        appointment = contact.models.Appointment(
            full_name=full_name,
            email=email,
            phone=phone,
            service=service,
            date=date,
            time=time,
            notes=notes
        )
        appointment.save()

        # Build message for logs
        message_text = (
            f"Appointment for {full_name} ({email}, {phone})\n"
            f"Service: {service}\n"
            f"Date: {date} at {time}\n"
            f"Notes: {notes}"
        )

        message = contact.models.Message(
            full_name="Hairitage Studio",
            email=settings.DEFAULT_FROM_EMAIL,
            message_text=message_text,
            subject="New Appointment"
        )
        message.save()

        # --- Send Emails ---
        with get_connection(
                host=settings.EMAIL_HOST,
                port=settings.EMAIL_PORT,
                username=settings.EMAIL_HOST_USER,
                password=settings.EMAIL_HOST_PASSWORD,
                use_tls=settings.EMAIL_USE_TLS
        ) as connection:
            # Acknowledgement to customer
            user_subject = "Your Appointment Confirmation – Hairitage Studio"
            user_body = render_to_string("site/emails/appointment_acknowledgment.html", {
                "full_name": full_name,
                "service": service,
                "date": date,
                "time": time,
            })
            user_email = EmailMessage(
                subject=user_subject,
                body=user_body,
                from_email="Hairitage Studio <noreply@hairitage-studio.co.za>",
                to=[email],
                reply_to=["info@hairitage-studio.co.za"],
                connection=connection
            )
            user_email.content_subtype = "html"
            user_email.send()

            # Notification to admin
            admin_subject = f"New Appointment: {full_name} - {service}"
            admin_body = render_to_string("site/emails/appointment_admin.html", {
                "full_name": full_name,
                "email": email,
                "phone": phone,
                "service": service,
                "date": date,
                "time": time,
                "notes": notes,
            })
            admin_email = EmailMessage(
                subject=admin_subject,
                body=admin_body,
                from_email="Hairitage Studio <noreply@hairitage-studio.co.za>",
                to=["info@hairitage-studio.co.za"],
                reply_to=[email],
                connection=connection
            )
            admin_email.content_subtype = "html"
            admin_email.send()

        messages.success(request, 'Your appointment has been successfully received. We’ve sent you a confirmation email.')

    return render(request, 'site/contact.html', {
        'services': work.models.Service.objects.all().order_by('name')
    })


def contact_page(request):
    if request.method == 'POST':
        full_name = request.POST.get('full_name')
        email = request.POST.get('email')
        message_text = request.POST.get('message_text')
        subject = request.POST.get('subject')

        message = contact.models.Message(full_name=full_name, email=email, message_text=message_text, subject=subject)
        message.save()

        send_email_with(message)
        messages.success(request, 'Your message has been successfully received.')
        return redirect('contact.html')

    services = work.models.Service.objects.all().order_by('name')

    return render(request, 'site/contact.html', {'services': services})


def service_page(request):
    promotion = product.models.Promotion.objects.filter(home_page=True).order_by('-created_at').first()
    context = {
        'promotion': promotion,
        'stats': configuration.models.Stats.objects.all()
    }
    return render(request, 'site/services.html', context)


def send_email_with(message):
    with get_connection(
            host=settings.EMAIL_HOST,
            port=settings.EMAIL_PORT,
            username=settings.EMAIL_HOST_USER,
            password=settings.EMAIL_HOST_PASSWORD,
            use_tls=settings.EMAIL_USE_TLS
    ) as connection:
        # --- Acknowledgement to the user ---
        user_subject = "Thanks for contacting Hairitage Studio"
        user_body = render_to_string("site/emails/contact_acknowledgment.html", {
            "full_name": message.full_name,
            "subject": message.subject,
        })

        ack_email = EmailMessage(
            subject=user_subject,
            body=user_body,
            from_email="Hairitage Studio <noreply@hairitage-studio.co.za>",
            to=[message.email],
            reply_to=[settings.DEFAULT_FROM_EMAIL],
            connection=connection,
        )
        ack_email.content_subtype = "html"
        ack_email.send()

        # --- Notification to system/admin ---
        admin_subject = f"New Inquiry: {message.subject}"
        admin_body = render_to_string("site/emails/contact_admin.html", {
            "full_name": message.full_name,
            "email": message.email,
            "subject": message.subject,
            "message_text": message.message_text,
        })

        admin_email = EmailMessage(
            subject=admin_subject,
            body=admin_body,
            from_email="Hairitage Studio <noreply@hairitage-studio.co.za>",
            to=["info@hairitage-studio.co.za"],
            reply_to=[message.email],
            connection=connection,
        )
        admin_email.content_subtype = "html"
        admin_email.send()


def work_page(request):
    cat_id = request.GET.get('cat_id')
    if cat_id is None:
        items = work.models.Item.objects.all().order_by('-created_at')
    else:
        items = work.models.Item.objects.filter(category_id=cat_id).order_by('-created_at')

    paginator = Paginator(items, int(ITEM_PER_PAGE))
    page = request.GET.get('page', 1)
    works = paginator.get_page(page)

    # Get main categories and prefetch their subcategories with item counts
    work_categories = (
        work.models.Category.objects
        .filter(parent_id__isnull=True)
        .prefetch_related('subcategories')
        .order_by('name')
    )

    subcategories = work.models.Category.objects.raw(
        """
        SELECT
            work_category.id,
            work_category.name,
            COUNT(work.*) as ct
        FROM work_category
        LEFT JOIN work
            ON work_category.id = work.category_id
        WHERE work_category.parent_id IS NOT NULL
        GROUP BY work_category.id
        ORDER BY work_category.name
        """
    )

    context = {
        'works': works,
        'range': range(1, works.paginator.num_pages + 1),
        'page': int(page),
        'work_categories': work_categories,
        'subcategories': subcategories,
    }
    return render(request, 'site/work.html', context)