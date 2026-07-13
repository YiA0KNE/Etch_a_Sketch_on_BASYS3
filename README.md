# Etch_a_Sketch_on_BASYS3

Autor Orheanu Stefan - Bogdan

# Revizii 
| Revizie   | Data          | Comentarii                                                                |
| :---      | :----         | :---                                                                      |
| 0.1       | 07.07.2026    | Definirea obiectivelor pentru proiect                                     |
| 0.2       | 10.07.2026    | Extinderea obiectivelor, finalizarea vga_controller si testarea acestuia  |

## Cuprins

- [Etch\_a\_Sketch\_on\_BASYS3](#etch_a_sketch_on_basys3)
- [Revizii](#revizii)
  - [Cuprins](#cuprins)
  - [Introducere](#introducere)
  - [Obiective principale](#obiective-principale)
  - [Etapele proiectului](#etapele-proiectului)
    - [1. Definirea obiectivelor](#1-definirea-obiectivelor)
    - [2. Simulare VGA](#2-simulare-vga)
    - [3. Implementare VGA](#3-implementare-vga)
    - [4. Test VGA](#4-test-vga)
    - [5. Cresterea rezolutiei](#5-cresterea-rezolutiei)
    - [6. Miscarea cursorului](#6-miscarea-cursorului)
    - [7. Marirea sau micsorarea cursorului](#7-marirea-sau-micsorarea-cursorului)
    - [8. Adaugarea unui reset pentru canvas](#8-adaugarea-unui-reset-pentru-canvas)
    - [9. Selectia culorii](#9-selectia-culorii)
    - [10. Interfata indicator de culoare](#10-interfata-indicator-de-culoare)
  - [Dificultati generale](#dificultati-generale)
  - [Hardware](#hardware)


## Introducere

Un Etch-A-Sketch digital/program de desen asemanator cu Krita, realizat in SystemVerilog pentru placa Basys 3, afisat in timp real prin VGA. Utilizatorul va putea sa schimbe culoarea, sa combine culori, sa stearga tot ecranul sau doar o portiune si sa schimbe marimea cursorului.

## Obiective principale

**Obiective proprii** — De invatat cum se implementeaza si se utilizeaza o placa FPGA si metode de optimizare.

**Obiective proiect** — De realizat o plansa de desen asemanatoare unui Etch-A-Sketch/Krita.

## Etapele proiectului

- [x] 1. **Definirea obiectivelor** — Definirea scopului proiectului.
- [x] 2. **Simulare VGA** — Simularea unui semnal VGA la rezolutia 640x480.
- [x] 3. **Implementare VGA** — Afisarea culorilor pe monitor.
- [x] 4. **Test VGA** — Afisarea unui patrat care se misca, pentru a testa functionalitatile.
- [ ] 5. **Cresterea rezolutiei** — Cresterea rezolutiei la 1024x768 la 60Hz.
- [ ] 6. **Miscarea cursorului** — Mutarea unui cursor pe ecran folosind butoanele de pe placa (posibil schimbat ulterior cu un Pmod).
- [ ] 7. **Marirea sau micsorarea cursorului** — Modificarea marimii cursorului.
- [ ] 8. **Adaugarea unui reset pentru canvas** — Un buton care va reseta tot ce este desenat pe ecran.
- [ ] 9. **Selectia culorii** — Trei butoane/switch-uri care selecteaza dintre culorile rosu, verde, albastru.
- [ ] 10. **Interfata indicator de culoare** — Un element UI care arata culoarea curenta, inclusiv combinatiile de culori.

### 1. Definirea obiectivelor

La finalul proiectului, doresc sa am un canvas si interfete pentru utilizator care afiseaza culoarea curenta, marimea cursorului si abilitatea de a sterge doar o portiune sau tot ecranul.

### 2. Simulare VGA

**Obiectiv**

Verificarea functionala a modulului _vga_controller.sv_ inainte de sinteza, pentru a confirma corectitudinea semnalului generat.

**Metoda de realizare**

Verificarea modulului _vga_controller.sv_ cu un testbench prestabilit. Acesta a verificat rezolutia, culoarea si cazul de reset in timpul afisarii imaginii.

**Dificultati**

Exemplul gasit pe internet a fost eronat, ceea ce a dus la timp pierdut si m-a obligat sa rescriu aproape in intregime modulul _vga_controller_.

**Mod de dezvoltare**

Am utilizat Vivado si un testbench standard. Am rulat simularea pana cand aceasta s-a terminat fara erori.

### 3. Implementare VGA

**Obiectiv**

Generarea semnalului VGA fizic la frecventa corecta, pentru a putea afisa imaginea pe monitor prin portul VGA al placii.

**Metoda de realizare**

Adaugarea unui _clk_wiz_ pe care l-am setat la 25.175MHz. Acesta poate fi modificat individual, fara a fi necesara editarea altor fisiere. Realizarea unui fisier _top_ in care am instantiat _clk_vga_wrapper_ si _vga_controller_.

**Mod de dezvoltare**

Constrangerile au fost preluate de pe site-ul Digilent si adaugate manual in proiect. Apoi am creat fisierul top.

### 4. Test VGA

**Obiectiv**

Testarea functionala a iesirii VGA pe monitor, folosind un element vizual dinamic usor de verificat cu ochiul liber.

**Metoda de realizare**

Realizarea unui modul numit _moving_square_gen_ care genereaza un patrat ce se misca pana intalneste o margine.

**Dificultati**

Patratul nu se misca din pozitia 0,0. Pentru a rezolva asta, am stocat pozitia curenta in variabila _next_dir_y_.

**Mod de dezvoltare**

Am reincarcat design-ul pe placa in mod repetat, pana am obtinut comportamentul dorit.

### 5. Cresterea rezolutiei

*(De completat — ce a trebuit schimbat fata de 640x480: clock, porturi, timing-uri noi.)*

### 6. Miscarea cursorului

*(De completat — cum ai mapat butoanele la miscarea cursorului, cum ai tratat debounce-ul.)*

### 7. Marirea sau micsorarea cursorului

*(De completat — cum se modifica dimensiunea cursorului si ce butoane/switch-uri controleaza asta.)*

### 8. Adaugarea unui reset pentru canvas

*(De completat — cum functioneaza reset-ul, ce memorie/buffer se goleste.)*

### 9. Selectia culorii

*(De completat — cum sunt mapate butoanele/switch-urile pe rosu, verde, albastru, cum se combina.)*

### 10. Interfata indicator de culoare

*(De completat — cum este afisata culoarea curenta pe ecran, ce logica sta in spate.)*

## Dificultati generale

1. Realizarea fisierului vga_controller.sv a fost o dificultate din cauza unui exemplu eronat gasit pe internet. In final, cu ajutor, am reusit sa il realizez.
2. ...
*(De completat pe masura ce apar — ex: probleme de timing, sincronizare VGA, resurse FPGA insuficiente, etc.)*

## Hardware

- Placa Digilent **Basys 3** (FPGA Artix-7)
- Monitor compatibil VGA
- Cablu VGA