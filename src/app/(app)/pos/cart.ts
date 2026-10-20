export type CatalogProduct = {
  id: string;
  category_id: string;
  name: string;
  price: number;
};

export type CartLine = { product: CatalogProduct; quantity: number };

// Insertion-ordered so lines stay where the cashier expects them.
export type Cart = Map<string, CartLine>;

export type CartAction =
  | { type: "add"; product: CatalogProduct }
  | { type: "set"; productId: string; quantity: number }
  | { type: "clear" };

export function cartReducer(cart: Cart, action: CartAction): Cart {
  const next = new Map(cart);
  switch (action.type) {
    case "add": {
      const line = next.get(action.product.id);
      next.set(action.product.id, {
        product: action.product,
        quantity: (line?.quantity ?? 0) + 1,
      });
      return next;
    }
    case "set": {
      const line = next.get(action.productId);
      if (!line) return cart;
      if (action.quantity <= 0) next.delete(action.productId);
      else next.set(action.productId, { ...line, quantity: action.quantity });
      return next;
    }
    case "clear":
      return new Map();
  }
}

export function cartTotals(cart: Cart) {
  let items = 0;
  let total = 0;
  for (const { product, quantity } of cart.values()) {
    items += quantity;
    total += product.price * quantity;
  }
  return { items, total: Math.round(total * 100) / 100 };
}

// Quick "amount received" buttons for cash: exact, next ₹50/₹100, common notes.
export function cashSuggestions(total: number) {
  const options = new Set<number>([
    total,
    Math.ceil(total / 50) * 50,
    Math.ceil(total / 100) * 100,
    200,
    500,
  ]);
  return [...options].filter((n) => n >= total).sort((a, b) => a - b).slice(0, 4);
}
