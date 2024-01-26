from django.contrib import admin
from .models import Category, Post, Comment
from .forms import PostForm


@admin.register(Category)
class PostAdmin(admin.ModelAdmin):
    list_display = ['name', ]
    list_filter = ['name']


@admin.register(Post)
class PostAdmin(admin.ModelAdmin):
    list_display = ['date', 'title', 'type', 'category_id', 'user_id']
    list_filter = ['title', 'date', 'type']
    form = PostForm


@admin.register(Comment)
class CommentAdmin(admin.ModelAdmin):
    list_display = ['user_id', 'post_id', 'created_at']
    list_filter = ['user_id', 'post_id', 'created_at']
