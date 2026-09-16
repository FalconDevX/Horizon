# Horizon — analiza i szczegółowe propozycje rozwoju

## 1. Stan obecny

Projekt ma już solidną bazę: proceduralnie generowany układ, planety i księżyce, fizykę orbit, lot statkiem, autopilota, lądowanie oraz osobny widok powierzchni. Największy problem nie leży w braku funkcji, lecz w tym, że część z nich jest słabo widoczna dla gracza albo zachowuje się inaczej w widoku kosmicznym i powierzchniowym.

Najważniejsze miejsca w kodzie:

- `scripts/main.gd` — wybór celu i globalne skróty klawiszowe.
- `scripts/universe.gd` — generowanie planet, promienie i prędkości orbit.
- `scripts/orbit_renderer.gd` — przewidywana orbita statku i zaznaczenie celu.
- `scripts/ship.gd` — sterowanie, kamera, autopilot i skala widoku kosmicznego.
- `scripts/surface_mode.gd` — lądowanie, lot nad powierzchnią i widok globu.
- `scripts/hud.gd` — cały interfejs gracza.
- `shaders/planet_sphere.gdshader` oraz `shaders/surface_globe.gdshader` — wygląd planet.

## 2. Edycja orbit planet

### Proponowane sterowanie

- `Tab` — następne ciało niebieskie.
- `Shift + Tab` — poprzednie ciało niebieskie.
- `[` i `]` — zmniejszenie lub zwiększenie promienia orbity wybranej planety o 2%.
- `Shift + [` i `Shift + ]` — precyzyjna zmiana promienia o 0,25%.
- `;` i `'` — zmniejszenie lub zwiększenie prędkości orbitalnej.
- `Ctrl + R` — przywrócenie fizycznej orbity kołowej dla aktualnego promienia.
- `O` — pokazanie lub ukrycie wszystkich orbit.
- `H` lub `F1` — otwarcie menu pomocy ze skrótami.

### Zasady działania

Zmiana promienia orbity powinna od razu przeliczać prędkość kołową ze wzoru używanego już przez `OrbitalPhysics`. Dzięki temu planeta nie będzie stopniowo „uciekała” z układu. Kierunek obiegu — zgodny lub przeciwny do wskazówek zegara — powinien zostać zachowany.

System powinien pilnować minimalnych odstępów między sąsiednimi orbitami. Minimalny bezpieczny odstęp można policzyć jako sumę promieni obu ciał pomnożoną przez 2,5 oraz dodatkowy margines. Przy próbie przekroczenia granicy HUD powinien pokazać komunikat „Orbita zbyt blisko sąsiedniej planety”.

Księżyce należy edytować względem ich planety nadrzędnej, a planety względem słońca. Zmiana orbity planety nie powinna zmieniać lokalnej orbity jej księżyców.

### Tryb edycji

Dobrym rozwiązaniem będzie osobny tryb „EDYCJA ORBITY”, włączany klawiszem `P`. W tym trybie:

- czas automatycznie zatrzymuje się;
- sterowanie statkiem jest zablokowane;
- zaznaczona orbita jest wyraźna i pulsuje;
- HUD pokazuje promień orbity, okres, prędkość oraz ciało nadrzędne;
- `Enter` zatwierdza zmianę, a `Esc` ją anuluje;
- przerywana linia pokazuje poprzednią orbitę, zanim gracz zatwierdzi zmianę.

To jest bezpieczniejsze i czytelniejsze niż ciągła edycja orbit podczas lotu.

## 3. Podświetlanie orbit i celów

Obecnie orbity planet są bardzo słabo widoczne, a wybrany cel otrzymuje głównie okrąg wokół samej planety. Proponowany system kolorów:

- orbity nieaktywne — cienka linia w kolorze stalowoniebieskim, 15–22% krycia;
- orbita wybranego celu — jasny cyjan, grubsza linia i delikatna poświata;
- orbita edytowana — bursztynowa linia z animowanym pulsem;
- orbita statku stabilna — niebieska;
- trajektoria ucieczkowa — pomarańczowa;
- trajektoria kolizyjna — czerwona;
- planowana orbita po zatwierdzeniu manewru — zielona linia przerywana.

Podświetlenie powinno mieć stałą grubość ekranową niezależnie od zoomu. Przy wybranej planecie można dodatkowo narysować pionowy znacznik nad planetą i małą strzałkę na krawędzi ekranu, gdy cel znajduje się poza kadrem.

Kliknięcie planety lub jej orbity powinno wybierać ją jako cel. Tolerancja kliknięcia powinna wynosić około 8–12 pikseli ekranowych, dzięki czemu wybór będzie łatwy również przy dużym oddaleniu.

## 4. Lepszy HUD

### Układ ekranu

HUD warto podzielić na stałe, logiczne obszary:

- lewy górny róg — kadłub, paliwo, energia i ostrzeżenia;
- środek u góry — kierunek lotu, prograde/retrograde i aktualny zoom;
- prawy górny róg — karta wybranego celu;
- lewy dolny róg — radar;
- środek na dole — tryby SAS, warp, autopilot, orbity i lądowanie;
- prawy dolny róg — prędkość, ciąg, wysokość i prędkość pionowa;

### Dane, których brakuje

- prędkość względem aktualnego ciała, a nie tylko prędkość absolutna;
- wysokość nad powierzchnią;
- prędkość pionowa i styczna;
- czas do perycentrum i apocentrum;
- nazwa ciała, względem którego liczona jest orbita;
- informacja, czy orbita jest stabilna, kolizyjna czy ucieczkowa;
- aktualny poziom zoomu i skala, np. „1 px = 240 m”;
- czy aktywny jest widok orbit i tryb ich edycji.

### Komunikaty kontekstowe

Zamiast jednego długiego ciągu skrótów na dole ekran powinien pokazywać maksymalnie 3–5 podpowiedzi pasujących do sytuacji. Przykłady:

- przy planecie: `L — rozpocznij lądowanie`;
- po wybraniu celu: `F — autopilot do celu`;
- w trybie edycji: `[ / ] — zmień promień`, `Enter — zatwierdź`, `Esc — anuluj`;
- po lądowaniu: `Spacja — start`, `WASD — lot nad powierzchnią`.

Ważne zdarzenia powinny pojawiać się jako krótkie powiadomienia, np. „Autopilot włączony”, „Brak paliwa”, „Niebezpieczna prędkość lądowania” albo „Orbita przywrócona”.

## 5. Menu klawiszy

Menu pomocy powinno otwierać się nad grą po `H` lub `F1`, zatrzymywać symulację i pokazywać skróty w grupach:

1. Lot: ciąg, obrót, RCS, SAS, zatrzymanie silnika.
2. Kamera: zoom, reset kadru, śledzenie celu.
3. Nawigacja: wybór celu, autopilot, lądowanie, orbity.
4. Edycja układu: promień orbity, prędkość, zatwierdzenie i anulowanie.
5. Powierzchnia: ruch, start, zoom i powrót do skali domyślnej.

Każdy skrót powinien wyglądać jak osobny „klawisz” z zaokrąglonym tłem. Menu musi poprawnie skalować się od 1280×720 wzwyż i przy mniejszych oknach przechodzić na układ dwukolumnowy lub przewijany.

## 6. Zachowanie skali przed i po lądowaniu

W kodzie istnieje już wspólna funkcja `ProcPlanet.target_screen_radius()`, co jest dobrym fundamentem. Widok kosmiczny i powierzchniowy korzystają jednak z różnych środków kadru, a powierzchnia ma dodatkowy własny zoom. To może powodować wizualny skok podczas przejścia.

Proponowane zasady:

- promień planety w pikselach w ostatniej klatce przed przejściem musi być równy promieniowi w pierwszej klatce widoku powierzchni;
- środek planety powinien pozostać w tym samym punkcie ekranu podczas przejścia;
- aktualny zoom powinien zostać przekazany do trybu powierzchni zamiast bezwarunkowo wracać do `100%`;
- przejście powinno trwać 0,35–0,5 s i być płynnym przenikaniem, bez nagłego przeskoku kamery;
- statek powinien zachować ten sam rozmiar ekranowy na granicy obu trybów;
- powrót w kosmos powinien odtwarzać skalę, z jaką gracz opuszczał planetę.

Najlepiej przechowywać jedną wartość „metry na piksel” i na jej podstawie wyliczać zoom obu kamer. Zapobiegnie to rozjeżdżaniu się skali dla bardzo małych księżyców i gazowych olbrzymów.

### Kryterium odbioru

Automatyczny test powinien porównać pozycję środka, promień planety i rozmiar statku przed oraz po przejściu. Dopuszczalna różnica: maksymalnie 1 piksel dla planety i 5% dla statku.

## 7. Bardziej szczegółowe powierzchnie planet

Obecny widok kosmiczny używa prawie wyłącznie koloru bazowego i prostego światła. Widok powierzchni ma więcej szumu, lecz nadal wszystkie typy planet korzystają z podobnego modelu terenu. Największą poprawę da wspólny, proceduralny shader używany w obu widokach.

### Warstwy powierzchni

1. Kontynenty — duży, wolnozmienny szum tworzący główne masy lądu.
2. Góry i grzbiety — szum typu ridge z ostrzejszymi krawędziami.
3. Drobny teren — kratery, uskoki, wydmy lub spękania zależne od typu planety.
4. Klimat — kolor zależny od szerokości geograficznej, wysokości i wilgotności.
5. Atmosfera — poświata na krawędzi, rozpraszanie światła i cień po nocnej stronie.
6. Chmury — osobna, wolniej obracająca się warstwa dla planet oceanicznych i toksycznych.
7. Światła lub emisja — lawa, burze gazowych olbrzymów i ewentualne światła kolonii.

### Charakter poszczególnych planet

- Oceaniczna: głębokie i płytkie oceany, plaże, zielone lądy, czapy polarne, półprzezroczyste chmury i refleks na wodzie.
- Pustynna: wydmy, płaskowyże, kratery, jaśniejsze równiny i pyłowa atmosfera.
- Lodowa: spękania lodu, ciemniejsze szczeliny, gładkie równiny i silny refleks.
- Lawowa: ciemna skorupa, świecące pęknięcia, gorące jeziora oraz czerwony poblask po nocnej stronie.
- Gazowa: pasy o różnej prędkości, wiry, wielkie burze, miękkie przejście przy krawędzi i cień pierścieni.
- Toksyczna: żółtozielone chmury, ciemne morza lub niziny, gęsta atmosfera i lokalne wyładowania.
- Węglowa: prawie czarna powierzchnia, fioletowe minerały, ostre jasne grzbiety i słaba atmosfera.

### Wydajność

Shader powinien mieć trzy poziomy jakości:

- niski — 3 oktawy szumu, bez chmur i bez drobnych kraterów;
- średni — 5 oktaw, chmury i podstawowe detale;
- wysoki — 6–7 oktaw, kratery, normal map wyliczany w shaderze i dodatkowe efekty atmosfery.

Przy dużym oddaleniu drobne detale należy wyłączyć, ponieważ i tak są niewidoczne. Pozwoli to zachować płynność mimo bogatszego wyglądu z bliska.

## 8. Dodatkowe usprawnienia

- Zapisywanie ziarna układu, zmian orbit i ustawień HUD-u do pliku zapisu.
- Pauza pod `Esc` z przyciskami: Wznów, Sterowanie, Ustawienia, Nowy układ, Wyjście.
- Suwaki głośności, jakości powierzchni i intensywności HUD-u.
- Tryb daltonistyczny, w którym typy orbit różnią się także wzorem linii, nie tylko kolorem.
- Znaczniki prograde, retrograde, radial-in i radial-out wokół statku.
- Planowanie manewru przez przeciągnięcie punktu na orbicie i podgląd przewidywanej trajektorii.
- Automatyczne ograniczenie warp przy zbliżaniu się do planety albo punktu przecięcia orbity.
- Kamera „śledź cel”, dzięki której planeta nie ucieka z kadru podczas obserwacji.

## 9. Proponowana kolejność wdrożenia

### Etap 1 — czytelność i spójność

- menu klawiszy;
- nowy układ HUD-u;
- wyraźne podświetlanie wybranej orbity;
- wskaźnik celu poza ekranem;
- zachowanie skali i środka planety podczas lądowania.

### Etap 2 — edycja orbit

- osobny tryb edycji;
- zmiana promienia i prędkości;
- podgląd starej i nowej orbity;
- walidacja odstępów;
- zapis zmian.

### Etap 3 — grafika planet

- wspólny proceduralny model powierzchni;
- indywidualne cechy każdego typu planety;
- chmury, atmosfera i emisja;
- poziomy jakości i optymalizacja.

### Etap 4 — nawigacja zaawansowana

- punkty manewrowe;
- przewidywanie spotkania z celem;
- czas do apsyd;
- bezpieczny warp i rozbudowany autopilot.

## 10. Definicja gotowego pierwszego wydania

Pierwszy pakiet zmian można uznać za ukończony, gdy:

- gracz może wybrać planetę myszą oraz klawiszami w obie strony;
- orbita wybranego ciała jest zawsze jednoznacznie podświetlona;
- tryb edycji pozwala bezpiecznie zmienić orbitę i cofnąć zmianę;
- pełna lista klawiszy jest dostępna w grze bez wychodzenia do dokumentacji;
- HUD pokazuje najważniejsze dane lotu i nie zasłania centralnej części ekranu;
- lądowanie nie powoduje widocznej zmiany rozmiaru ani położenia planety;
- planety z bliska mają rozpoznawalne, różniące się powierzchnie;
- testy fizyki orbitalnej i przejścia do powierzchni nadal przechodzą.
