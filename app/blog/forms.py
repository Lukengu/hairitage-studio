from django import forms
from .models import Post


class PostForm(forms.ModelForm):
    class Meta:
        model = Post
        fields = ['title', 'category_id', 'intro', 'content', 'status', 'image', 'user_id', 'comment_count', 'type']
        widgets = {
            'comment_count': forms.HiddenInput(),
        }
