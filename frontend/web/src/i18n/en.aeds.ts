/** English texts of one area, keyed by the Polish source text passed to `t`. */
export const EN_AEDS: Record<string, string> = {
  // Weekdays and units
  'Poniedziałek': 'Monday',
  'Wtorek': 'Tuesday',
  'Środa': 'Wednesday',
  'Czwartek': 'Thursday',
  'Piątek': 'Friday',
  'Sobota': 'Saturday',
  'Niedziela': 'Sunday',
  'min': 'min',
  'm': 'm',
  'km': 'km',

  // Status
  'AED niedostępny': 'AED unavailable',
  'Dostęp niepotwierdzony': 'Access not confirmed',
  'Niedostępny': 'Not available',
  'Brak informacji o dostępie': 'No access information',
  'Dostępny do {time}': 'Available until {time}',
  'Dostęp całodobowy': 'Open 24/7',
  'Teraz zamknięty': 'Closed now',
  'Otwarcie o {time}': 'Opens at {time}',
  'Brak informacji o godzinach': 'No opening hours information',
  'Wg źródła: {text}': 'Per source: {text}',
  'Wewnątrz budynku': 'Inside the building',
  'Na zewnątrz': 'Outside',
  'parter': 'ground floor',
  'piętro {n}': 'floor {n}',
  'poziom {n}': 'level {n}',

  // Hours
  'Niezweryfikowane. Godziny odczytane ze źródła, nie używamy ich do wskazywania dostępności.':
    'Unverified. Hours read from the source; we do not use them to show availability.',
  'Całodobowo, 7 dni w tygodniu': 'Open 24 hours, 7 days a week',
  'Wg źródła:': 'Per source:',
  'Brak informacji o godzinach, więc traktujemy AED jako niedostępny.': 'No hours information, so we treat this AED as unavailable.',
  'zamknięte': 'closed',
  'niedostępny (brak danych)': 'unavailable (no data)',

  // Finding guide
  'Źródło nie opisuje wejścia. Zapytaj obsługę lub ochronę budynku.': 'The source does not describe the entrance. Ask building staff or security.',
  'Dostęp może wymagać pomocy obsługi lub ochrony budynku.': 'Access may need help from building staff or security.',
  'Jak znaleźć urządzenie': 'How to find the device',
  'Szukaj zielonego znaku AED z sercem i błyskawicą. Szafka zwykle wisi przy wejściu, recepcji lub windach.':
    'Look for the green AED sign with a heart and lightning bolt. The cabinet is usually near the entrance, reception or lifts.',
  'Miejsce defibrylatora: {name}': 'Defibrillator location: {name}',

  // Usage guide
  'Sprawdź, czy oddycha': 'Check if they are breathing',
  'Jeśli poszkodowany nie reaguje i nie oddycha prawidłowo, działaj od razu.': 'If the person does not respond and is not breathing normally, act at once.',
  'Zadzwoń pod 112': 'Call 112',
  'Włącz głośnik. Jeśli ktoś jest obok, niech przyniesie AED, a Ty zostań przy poszkodowanym.':
    'Turn on speakerphone. If someone is nearby, ask them to bring the AED while you stay with the person.',
  'Uciskaj klatkę piersiową': 'Press on the chest',
  'Środek klatki, na głębokość 5–6 cm, 100–120 razy na minutę. Nie przerywaj, dopóki AED nie jest gotowy.':
    'Centre of the chest, 5–6 cm deep, 100–120 times a minute. Do not stop until the AED is ready.',
  'Włącz AED': 'Turn on the AED',
  'Otwórz pokrywę lub naciśnij przycisk zasilania. Urządzenie mówi, co robić: wykonuj jego polecenia.':
    'Open the lid or press the power button. The device tells you what to do: follow its instructions.',
  'Naklej elektrody': 'Attach the pads',
  'Na odsłoniętą, suchą klatkę: pod prawym obojczykiem i na lewym boku pod pachą, jak na rysunku.':
    'On bare, dry skin: below the right collarbone and on the left side under the armpit, as in the picture.',
  'Nie dotykaj podczas analizy': 'Do not touch during analysis',
  'Odsuń wszystkich. Jeśli AED zaleci wyładowanie, upewnij się, że nikt nie dotyka poszkodowanego, i naciśnij przycisk.':
    'Make everyone step back. If the AED advises a shock, make sure nobody touches the person, then press the button.',
  'Wróć do uciskania': 'Go back to chest compressions',
  'Zaraz po wyładowaniu lub komunikacie AED. Kontynuuj do przyjazdu pogotowia.':
    'Right after the shock or the AED message. Continue until the ambulance arrives.',
  'Jak użyć defibrylatora': 'How to use a defibrillator',
  'Według wytycznych Europejskiej Rady Resuscytacji. AED nie wyładuje się, jeśli nie jest to potrzebne.':
    'Based on European Resuscitation Council guidelines. The AED will not give a shock if one is not needed.',

  // Other
  'Dane: m.st. Warszawa, SCB (CC BY)': 'Data: City of Warsaw, SCB (CC BY)',
  'Zamknij': 'Close',
  'Zwiń szczegóły': 'Collapse details',
  'Pokaż szczegóły': 'Show details',
}
