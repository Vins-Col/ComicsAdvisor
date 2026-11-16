-- ComicsAdvisor MVP initial taxonomies.
-- This seed is intentionally idempotent and may be executed repeatedly.

insert into public.categories (
  name,
  slug,
  description,
  icon_name,
  is_active,
  sort_order
)
values
  (
    'Comics',
    'comics',
    'Fumetti, editoria e cultura legata al fumetto.',
    'book-open',
    true,
    10
  ),
  (
    'Manga e anime',
    'manga-anime',
    'Manga, anime e cultura pop giapponese.',
    'sparkles',
    true,
    20
  ),
  (
    'Cosplay',
    'cosplay',
    'Cosplay, contest, esibizioni e attività dedicate.',
    'shirt',
    true,
    30
  ),
  (
    'Videogiochi',
    'videogiochi',
    'Videogiochi, retrogaming, tornei e aree gaming.',
    'gamepad-2',
    true,
    40
  ),
  (
    'Giochi da tavolo',
    'giochi-da-tavolo',
    'Giochi da tavolo, dimostrazioni e attività ludiche.',
    'dice-5',
    true,
    50
  ),
  (
    'Giochi di carte',
    'giochi-di-carte',
    'Giochi di carte collezionabili, tornei e scambi.',
    'layers-3',
    true,
    60
  ),
  (
    'Collezionismo',
    'collezionismo',
    'Oggetti da collezione, memorabilia e prodotti vintage.',
    'archive',
    true,
    70
  ),
  (
    'Handmade',
    'handmade',
    'Creazioni artigianali e prodotti realizzati a mano.',
    'palette',
    true,
    80
  ),
  (
    'Artist Alley',
    'artist-alley',
    'Artisti indipendenti, illustratori e autoproduzioni.',
    'pen-tool',
    true,
    90
  ),
  (
    'Cinema e serie TV',
    'cinema-serie-tv',
    'Cinema, serie televisive, incontri e contenuti tematici.',
    'clapperboard',
    true,
    100
  ),
  (
    'Cultura pop',
    'cultura-pop',
    'Intrattenimento e cultura pop non compresi nelle altre categorie.',
    'star',
    true,
    110
  ),
  (
    'Food',
    'food',
    'Ristorazione, prodotti alimentari e aree food.',
    'utensils',
    true,
    120
  )
on conflict (slug) do update
set
  name = excluded.name,
  description = excluded.description,
  icon_name = excluded.icon_name,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order;


insert into public.exhibitor_categories (
  name,
  slug,
  is_active,
  sort_order
)
values
  ('Fumetti ed editoria', 'fumetti-editoria', true, 10),
  ('Manga e anime', 'manga-anime', true, 20),
  ('Carte collezionabili', 'carte-collezionabili', true, 30),
  ('Giochi da tavolo', 'giochi-da-tavolo', true, 40),
  ('Videogiochi e retrogaming', 'videogiochi-retrogaming', true, 50),
  ('Handmade e artigianato', 'handmade-artigianato', true, 60),
  ('Artista e illustratore', 'artista-illustratore', true, 70),
  ('Abbigliamento e accessori', 'abbigliamento-accessori', true, 80),
  ('Gadget e merchandising', 'gadget-merchandising', true, 90),
  ('Collezionismo', 'collezionismo', true, 100),
  ('Cosplay e props', 'cosplay-props', true, 110),
  ('Food e beverage', 'food-beverage', true, 120),
  ('Associazione', 'associazione', true, 130),
  ('Altro', 'altro', true, 140)
on conflict (slug) do update
set
  name = excluded.name,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order;
