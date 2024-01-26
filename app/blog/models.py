from django.db import models
from django.contrib.auth.models import User
from tinymce.models import HTMLField


class Category(models.Model):
    id = models.AutoField(primary_key=True)
    name = models.CharField(max_length=100)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.name

    class Meta:
        verbose_name_plural = "categories"


class Post(models.Model):
    STATUSES = [
        ('DRAFT', 'draft'),
        ('PUBLISH', 'publish'),
    ]

    TYPES = [
        ('blog', 'blog'),
        ('content', 'content'),
    ]

    id = models.AutoField(primary_key=True)
    title = models.CharField(max_length=100)
    intro = models.TextField()
    content = HTMLField()
    status = models.CharField(max_length=100, choices=STATUSES, default='draft')
    image = models.ImageField(upload_to='blogs/')
    user_id = models.ForeignKey(User, on_delete=models.CASCADE)
    category_id = models.ForeignKey(Category, on_delete=models.CASCADE, default=3)
    type = models.CharField(max_length=100, choices=TYPES, default='blog')
    date = models.DateField(auto_now_add=True)
    comment_count = models.IntegerField(default=0)

    def __str__(self):
        return self.title

    class Meta:
        ordering = ('title', 'date')


class Comment(models.Model):
    id = models.AutoField(primary_key=True)
    created_at = models.DateField(auto_now_add=True)
    user_id = models.ForeignKey(User, on_delete=models.CASCADE)
    post_id = models.ForeignKey(Post, on_delete=models.CASCADE)
    content = models.TextField()
