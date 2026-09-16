# Audyt projektu — autopilot i skala statku

## Wniosek

Sieć neuronowa nie jest właściwym rozwiązaniem dla tego projektu. Stan lotu jest w pełni znany: pozycja, prędkość, masa, ciąg, grawitacja i docelowa orbita. Deterministyczny algorytm orbitalny da wynik powtarzalny, łatwy do testowania i łatwy do poprawienia; sieć wymagałaby tysięcy poprawnie zasymulowanych lotów, a mimo tego mogłaby rozbić statek w sytuacji, której nie widziała podczas treningu.

## Co już jest w projekcie

- Fizyczne elementy orbity: energia, mimośród, perycentrum i apocentrum (`scripts/orbital_physics.gd`).
- Sfera wpływu planet i przejście do orbity słonecznej (`scripts/universe.gd`).
- Zmieniana przez gracza wysokość docelowej orbity.
- Podgląd trajektorii i ochrona przed bezpośrednim lotem w powierzchnię.
- Sterowanie modułowym statkiem o stałym przyspieszeniu 12 m/s².

To oznacza, że fundament jest wystarczający — trzeba uporządkować decyzje autopilota, a nie zastępować je AI.

## Dlaczego obecny autopilot potrafi się mylić

Metoda `get_autopilot_guidance_for_state()` jednocześnie próbuje:

1. przewidzieć spotkanie z planetą;
2. ustalić kierunek orbity;
3. podejść do sfery wpływu;
4. podnieść perycentrum;
5. dobrać prędkość transferową;
6. ustabilizować okrąg.

Decyzje są przeliczane w każdej klatce. Po drobnej zmianie promienia albo prędkości autopilot może przełączyć warunek między `transfer`, `approach` i `circularize`, a następnie zmienić kierunek ciągu. Dodatkowo ograniczenie „nigdy nie ciągnij do środka” jest bezpieczne przy niskim przelocie, ale poza bezpieczną wysokością blokuje manewry, które są potrzebne do obniżenia orbity.

Obecny zielony tor jest wizualizacją tej samej chwilowej heurystyki, a nie niezależnym planem manewru. Dlatego może wyglądać wiarygodnie, ale nie musi odpowiadać późniejszemu zachowaniu statku.

## Zalecany algorytm: plan manewrów + regulator PD

Autopilot powinien najpierw utworzyć plan, a dopiero potem go wykonać. Plan należy przeliczać tylko po ważnym zdarzeniu: wejściu do sfery wpływu, wykonaniu manewru, zmianie wysokości celu przez gracza lub odchyleniu od planu większym niż ustalony próg.

### Faza 1 — wybór docelowej orbity

- `r_docelowe = promień planety + wysokość wybrana przez gracza`.
- `v_kołowe = sqrt(mu / r_docelowe)`.
- Kierunek CW/CCW wybierany raz, na starcie, według najmniejszego kosztu zmiany prędkości.

### Faza 2 — transfer

Dla lotu wewnątrz jednej sfery wpływu użyć transferu Hohmanna. Liczone są dwa impulsy:

- pierwszy zmienia apocentrum lub perycentrum do promienia docelowego;
- drugi, w przeciwnej apsydzie, wyrównuje prędkość do `v_kołowe`.

Przy locie między planetami należy wyliczyć punkt przecięcia z przyszłą pozycją celu i zaplanować hamowanie przed wejściem do jego sfery wpływu. W pierwszej wersji wystarczy iteracyjne przewidywanie pozycji planety co 0,5–1 s; nie trzeba od razu implementować pełnego rozwiązania Lamberta.

### Faza 3 — wykonanie pojedynczego manewru

Każdy manewr ma: punkt rozpoczęcia, wektor delta-v, tolerancję i status. Statek obraca się do wektora; po błędzie kierunku mniejszym niż około 3° włącza ciąg. Ciąg kończy się wcześniej o połowę czasu potrzebnego na wykonanie ostatniego kroku (tzw. burn-centering), żeby nie przestrzelić delta-v.

### Faza 4 — stabilizacja orbity

Po drugim manewrze użyć regulatora PD w lokalnych osiach promieniowej i stycznej:

`v_zadana = styczna * v_kołowe + promieniowa * clamp(-Kp * (r-r_docelowe) - Kd * v_promieniowa)`.

Regulator jest aktywny tylko blisko celu, np. w pasie ±10% docelowej wysokości. Po utrzymaniu błędu promienia i prędkości przez kilka sekund autopilot przechodzi w stan `ORBITA UTRZYMANA` i wyłącza silnik.

### Bezpieczeństwo

- Minimalne perycentrum: atmosfera + 10–20% marginesu.
- Zawsze wolno ciągnąć od planety, jeżeli przewidywane perycentrum jest za niskie.
- Ciąg do środka wolno włączyć tylko powyżej bezpiecznej wysokości i tylko w zaplanowanym manewrze obniżania orbity.
- Jeżeli brakuje paliwa na zaplanowane hamowanie, autopilot powinien przejść w `ABORT`, nie próbować „ratować” lotu chaotycznymi impulsami.

## Plan implementacji

1. Dodać klasę `AutopilotPlan` i obiekt `Maneuver` (bez zmiany renderowania).
2. Zastąpić ciągłe przełączanie faz listą manewrów o stałym celu.
3. Użyć istniejącego `OrbitalPhysics.elements()` do wyznaczania apsyd i czasu do manewru.
4. Zbudować osobny symulator bez renderowania i przetestować: start, podniesienie orbity, obniżenie orbity, wejście z dużą prędkością, orbitę CW i CCW.
5. Dopiero potem podłączyć zielony podgląd do rzeczywistego planu.

## Skala statku

Statek powinien pozostać elementem świata: przy oddalaniu kamery ma proporcjonalnie maleć, a przy zbliżaniu rosnąć. Tę samą skalę fizyczną należy stosować w kosmosie i nad powierzchnią, aby przejście między widokami nie zmieniało jego rozmiaru względem planety.

## Dalsze problemy do poprawienia

- Widok powierzchni nakłada nieprzezroczyste nocne tło; trzeba dodać czytelniejszą warstwę atmosfery i sprawdzić kontrast planety w realnej rozgrywce.
- Shader powierzchni jest kosztowny (wielokrotny szum oraz pochodne ekranu); potrzebuje automatycznego LOD zależnego od wielkości planety na ekranie.
- Trajektoria autopilota obecnie jest generowana osobnym przybliżeniem. Po dodaniu planu manewrów powinna korzystać z tego samego symulatora co autopilot.
- Testy sprawdzają pojedyncze kroki i właściwości matematyczne, ale brakuje testów pełnego lotu od startu do stabilnej orbity.
