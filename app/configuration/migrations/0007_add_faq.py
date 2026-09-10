from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('configuration', '0006_add_tiktok'),
    ]

    operations = [
        migrations.CreateModel(
            name='FAQ',
            fields=[
                ('id', models.AutoField(primary_key=True, serialize=False)),
                ('question', models.CharField(max_length=255)),
                ('answer', models.TextField()),
                ('order', models.PositiveIntegerField(default=0, help_text='Lower numbers appear first.')),
                ('is_active', models.BooleanField(default=True, help_text='Untick to hide this question from the site.')),
                ('created_at', models.DateField(auto_now_add=True)),
                ('updated_at', models.DateField(auto_now=True)),
            ],
            options={
                'verbose_name': 'FAQ',
                'verbose_name_plural': 'FAQs',
                'ordering': ('order', 'id'),
            },
        ),
    ]
