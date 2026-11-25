from pydantic import BaseModel


class Product(BaseModel):
    id: int
    sku: str
    name: str
    description: str
    category: str
    price_cents: int
    stock: int
    image: str

    @property
    def in_stock(self) -> bool:
        return self.stock > 0
