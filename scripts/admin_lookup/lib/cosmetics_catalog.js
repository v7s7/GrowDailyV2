'use strict';

/**
 * The built-in character, accessory and prestige-rank text, transcribed
 * once from lib/features/character/models/character_option.dart
 * (CharacterCatalog), accessory.dart (AccessoryCatalog) and
 * prestige_tier.dart (PrestigeCatalog). Static for the same reason
 * achievements_catalog.js is: these change rarely enough that a hand-kept
 * copy is simpler and safer than a second code-parsing pipeline. See that
 * file's own doc comment for what happens if this ever drifts behind the
 * Dart source (nothing unsafe: an unrecognised id just cannot be edited
 * here).
 */

const CATEGORIES = [
  { id: 'misbah', label: 'Tasbih', labelAr: 'مسباح' },
  { id: 'umbrella', label: 'Umbrella', labelAr: 'مظلة' },
  { id: 'frame', label: 'Frame', labelAr: 'إطار' },
  { id: 'badge', label: 'Badge', labelAr: 'شارة' },
  { id: 'lantern', label: 'Lantern', labelAr: 'فانوس' },
  { id: 'notebook', label: 'Notebook', labelAr: 'دفتر' },
];

// PrestigeCatalog.tiers, in ladder order. 'resolute' (level 15) was added
// 2026-09-21 to bisect the level 10-to-20 gap — see that tier's own doc
// comment in prestige_tier.dart.
const PRESTIGE_TIERS = [
  { id: 'seeker', minLevel: 1, title: 'Seeker', titleAr: 'الباحث' },
  { id: 'devoted', minLevel: 5, title: 'Devoted', titleAr: 'الملتزم' },
  { id: 'steadfast', minLevel: 10, title: 'Diligent', titleAr: 'المجتهد' },
  { id: 'resolute', minLevel: 15, title: 'Persistent', titleAr: 'المثابر' },
  { id: 'radiant', minLevel: 20, title: 'Steadfast', titleAr: 'الثابت' },
  { id: 'luminous', minLevel: 35, title: 'Accomplished', titleAr: 'المنجز' },
  { id: 'exalted', minLevel: 50, title: 'Distinguished', titleAr: 'المتميز' },
  { id: 'venerable', minLevel: 75, title: 'Honored', titleAr: 'المكرَّم' },
  { id: 'eternal_light', minLevel: 100, title: 'Legacy', titleAr: 'الإرث' },
];

const CHARACTERS = [
  { id: 'male_ghutra_blue', gender: 'male', name: 'Blue Ghutra', nameAr: 'الغترة الزرقاء' },
  { id: 'male_bisht_gold', gender: 'male', name: 'Gold Bisht', nameAr: 'البشت الذهبي' },
  { id: 'male_bisht_black', gender: 'male', name: 'Black Bisht', nameAr: 'البشت الأسود' },
  { id: 'male_bisht_grey', gender: 'male', name: 'Grey Bisht', nameAr: 'البشت الرمادي' },
  { id: 'male_thobe_cream', gender: 'male', name: 'Cream Thobe', nameAr: 'الثوب الكريمي' },
  { id: 'male_daglah_brown', gender: 'male', name: 'Brown Daglah', nameAr: 'الدقلة البنية' },
  { id: 'male_daglah_navy', gender: 'male', name: 'Navy Daglah', nameAr: 'الدقلة الكحلية' },
  { id: 'male_daglah_maroon', gender: 'male', name: 'Maroon Daglah', nameAr: 'الدقلة العنابية' },
  { id: 'male_daglah_olive', gender: 'male', name: 'Olive Daglah', nameAr: 'الدقلة الزيتية' },
  { id: 'male_daglah_black', gender: 'male', name: 'Black Daglah', nameAr: 'الدقلة السوداء' },
  { id: 'male_shmagh_red', gender: 'male', name: 'Red Shemagh', nameAr: 'الشماغ الأحمر' },
  { id: 'female_hijab_pink', gender: 'female', name: 'Pink Hijab', nameAr: 'الحجاب الوردي' },
  { id: 'female_niqab', gender: 'female', name: 'Niqab', nameAr: 'النقاب' },
  { id: 'female_hijab_teal', gender: 'female', name: 'Embroidered Look', nameAr: 'الزي المطرز' },
  { id: 'female_abaya_navy', gender: 'female', name: 'Navy Abaya', nameAr: 'العباءة الكحلية' },
  { id: 'female_hijab_olive', gender: 'female', name: 'Olive Look', nameAr: 'الزي الزيتي' },
];

const ACCESSORIES = [
  { id: 'misbah_amber', category: 'misbah', name: 'Amber Tasbih', nameAr: 'مسباح كهرمان', description: 'A calm companion that shines with your daily practice.', descriptionAr: 'رفيق هادئ يلمع مع وردك اليومي.' },
  { id: 'misbah_wood', category: 'misbah', name: 'Wooden Tasbih', nameAr: 'مسباح خشبي', description: 'Simple and warm, for steady daily habits.', descriptionAr: 'بسيط ودافئ للمداومة اليومية.' },
  { id: 'misbah_black', category: 'misbah', name: 'Black Tasbih', nameAr: 'مسباح أسود', description: 'Sleek and elegant, for long streaks.', descriptionAr: 'هادئ وأنيق لأصحاب السلاسل الطويلة.' },
  { id: 'misbah_blue', category: 'misbah', name: 'Blue Tasbih', nameAr: 'مسباح أزرق', description: 'Sea-calm, for the quiet part of the day.', descriptionAr: 'أزرق هادئ، يريّح العين.' },
  { id: 'misbah_red', category: 'misbah', name: 'Red Tasbih', nameAr: 'مسباح أحمر', description: 'Warmth to keep the evening adhkar company.', descriptionAr: 'لون دافئ يناسب أذكار المساء.' },
  { id: 'umbrella_blue', category: 'umbrella', name: 'Blue Umbrella', nameAr: 'مظلة زرقاء', description: 'A gentle touch to match the blue ghutra.', descriptionAr: 'لمسة لطيفة تناسب الغترة الزرقاء.' },
  { id: 'umbrella_gold', category: 'umbrella', name: 'Gold Umbrella', nameAr: 'مظلة ذهبية', description: 'A luxurious touch to match the gold bisht.', descriptionAr: 'لمسة فاخرة تناسب البشت الذهبي.' },
  { id: 'umbrella_red', category: 'umbrella', name: 'Red Umbrella', nameAr: 'مظلة حمراء', description: 'A bold touch to match the red shemagh.', descriptionAr: 'لمسة جريئة تناسب الشماغ الأحمر.' },
  { id: 'frame_gold', category: 'frame', name: 'Golden Frame', nameAr: 'إطار ذهبي', description: 'A radiant frame around your companion.', descriptionAr: 'إطار نوراني يظهر حول رفيقك.' },
  { id: 'badge_knowledge', category: 'badge', name: "Scholar's Badge", nameAr: 'شارة طالب علم', description: 'A small badge for those who keep learning.', descriptionAr: 'شارة صغيرة لمن يثبت على التعلم.' },
  { id: 'lantern_gold', category: 'lantern', name: 'Golden Lantern', nameAr: 'فانوس ذهبي', description: 'A steady light for a long journey.', descriptionAr: 'نور دائم لمن واصل رحلة العلم.' },
  { id: 'notebook_teal', category: 'notebook', name: 'Teal Notebook', nameAr: 'دفتر مميز', description: 'An elegant notebook for very long streaks.', descriptionAr: 'دفتر أنيق لأصحاب السلاسل الطويلة جدًا.' },
];

const CHARACTERS_BY_ID = new Map(CHARACTERS.map((c) => [c.id, c]));
const ACCESSORIES_BY_ID = new Map(ACCESSORIES.map((a) => [a.id, a]));
const CATEGORIES_BY_ID = new Map(CATEGORIES.map((c) => [c.id, c]));
const PRESTIGE_TIERS_BY_ID = new Map(PRESTIGE_TIERS.map((t) => [t.id, t]));

module.exports = {
  CATEGORIES, CHARACTERS, ACCESSORIES, PRESTIGE_TIERS,
  CHARACTERS_BY_ID, ACCESSORIES_BY_ID, CATEGORIES_BY_ID, PRESTIGE_TIERS_BY_ID,
};
