from django.db import models


class Service(models.Model):
    id = models.AutoField(primary_key=True)
    name = models.CharField(max_length=100, unique=True)
    icon = models.TextField()
    description = models.TextField()
    created_at = models.DateField(auto_now_add=True)

    def __str__(self):
        return self.name

    class Meta:
        ordering = ('name',)


class Team(models.Model):
    id = models.AutoField(primary_key=True)
    name = models.CharField(max_length=100, unique=True)
    photo = models.ImageField(upload_to='teams/')
    position = models.CharField(max_length=100)
    intro = models.TextField()
    created_at = models.DateField(auto_now_add=True)

    def __str__(self):
        return self.name

    class Meta:
        ordering = ('name', 'position', 'created_at')


class Category(models.Model):
    """
    Represents a category of hairdressing works.
    Example: 'Haircuts', 'Coloring', 'Styling'
    """
    id = models.AutoField(primary_key=True)
    name = models.CharField(max_length=255, unique=True)
    description = models.TextField(blank=True, null=True)
    created_at = models.DateField(auto_now_add=True)
    updated_at = models.DateField(auto_now=True)
    featured_image = models.ImageField(upload_to="category_images/", blank=True, null=True)
    parent = models.ForeignKey(
        'self',
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='subcategories'
    )

    def __str__(self):
        return self.name

    class Meta:
        verbose_name = "Work Category"
        verbose_name_plural = "Work Categories"
        db_table = "work_category"
        ordering = ('name', 'created_at')


class Item(models.Model):
    """
    Represents a hairdressing work item in a category.
    """
    category = models.ForeignKey(
        Category,
        on_delete=models.CASCADE,
        related_name="works"
    )
    title = models.CharField(max_length=255, blank=True, null=True)
    image = models.ImageField(upload_to="works/")
    description = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateField(auto_now=True)

    def __str__(self):
        return self.title or f"{self.category.name} work #{self.id}"

    class Meta:
        verbose_name = "Hair Work"
        verbose_name_plural = "Hair Works"
        db_table = "work"
