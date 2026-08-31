from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('configuration', '0005_rename_setting_settings_rename_stat_stats_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='settings',
            name='tiktok',
            field=models.CharField(blank=True, max_length=100, null=True),
        ),
    ]
