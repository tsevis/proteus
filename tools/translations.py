"""Writes Resources/Localization/<lang>.lproj/Localizable.strings.

English is the source language: the English text in the Swift code is the key,
and the app falls back to it for any language not listed here.
Usage: python3 tools/translations.py
"""
import pathlib

from translations_v11 import T as T_V11

LANGS = ["el", "it", "de", "uk"]

T = {
    "Rename (%lld)?": ["Μετονομασία (%lld);", "Rinominare (%lld)?", "Umbenennen (%lld)?", "Перейменувати (%lld)?"],
    "Rename": ["Μετονομασία", "Rinomina", "Umbenennen", "Перейменувати"],
    "Move to Trash (%lld)?": ["Μεταφορά στον Κάδο (%lld);", "Spostare nel Cestino (%lld)?",
                              "In den Papierkorb legen (%lld)?", "Перемістити в Смітник (%lld)?"],
    "Move to Trash": ["Στον Κάδο", "Sposta nel Cestino", "In den Papierkorb", "У Смітник"],
    "Folder…": ["Φάκελος…", "Cartella…", "Ordner …", "Папка…"],
    "Search": ["Αναζήτηση", "Cerca", "Suchen", "Шукати"],
    "Files": ["Αρχεία", "File", "Dateien", "Файли"],
    "Folders": ["Φάκελοι", "Cartelle", "Ordner", "Папки"],
    "Hidden": ["Κρυφά", "Nascosti", "Versteckte", "Приховані"],
    "Match case": ["Πεζά/κεφαλαία", "Maiuscole/minuscole", "Groß-/Kleinschreibung", "Враховувати регістр"],
    "Regex": ["Regex", "Regex", "Regex", "Regex"],
    "Name": ["Όνομα", "Nome", "Name", "Назва"],
    "New name": ["Νέο όνομα", "Nuovo nome", "Neuer Name", "Нова назва"],
    "Location": ["Θέση", "Posizione", "Ort", "Розташування"],
    "All": ["Όλα", "Tutti", "Alle", "Усі"],
    "None": ["Κανένα", "Nessuno", "Keine", "Жодного"],
    "Choose a folder and type what you are looking for.": [
        "Διάλεξε φάκελο και γράψε τι ψάχνεις.", "Scegli una cartella e scrivi cosa cerchi.",
        "Wähle einen Ordner und gib ein, wonach du suchst.", "Виберіть папку й введіть, що шукаєте."],
    "Choose": ["Επιλογή", "Scegli", "Auswählen", "Вибрати"],
    "Invalid regular expression: %@": ["Μη έγκυρη κανονική έκφραση: %@", "Espressione regolare non valida: %@",
                                       "Ungültiger regulärer Ausdruck: %@", "Недійсний регулярний вираз: %@"],
    "Searching…": ["Αναζήτηση…", "Ricerca…", "Suche …", "Пошук…"],
    "Found: %lld": ["Βρέθηκαν: %lld", "Trovati: %lld", "Gefunden: %lld", "Знайдено: %lld"],
    "Search error: %@": ["Σφάλμα αναζήτησης: %@", "Errore di ricerca: %@", "Suchfehler: %@", "Помилка пошуку: %@"],
    "Settings changed. Press Search again.": [
        "Οι ρυθμίσεις άλλαξαν. Πάτα ξανά Αναζήτηση.", "Le impostazioni sono cambiate. Premi di nuovo Cerca.",
        "Die Einstellungen haben sich geändert. Klicke erneut auf Suchen.",
        "Налаштування змінилися. Натисніть «Шукати» ще раз."],
    "Renamed: %lld": ["Μετονομάστηκαν: %lld", "Rinominati: %lld", "Umbenannt: %lld", "Перейменовано: %lld"],
    "Moved to Trash: %lld": ["Στον Κάδο: %lld", "Spostati nel Cestino: %lld", "In den Papierkorb gelegt: %lld",
                             "Переміщено в Смітник: %lld"],
    "Failed: %lld": ["Απέτυχαν: %lld", "Non riusciti: %lld", "Fehlgeschlagen: %lld", "Не вдалося: %lld"],
    "Invalid new name “%@”": ["Μη έγκυρο νέο όνομα «%@»", "Nuovo nome non valido «%@»",
                              "Ungültiger neuer Name „%@“", "Недійсна нова назва «%@»"],
    "“%@” already exists in the same folder": ["Υπάρχει ήδη «%@» στον ίδιο φάκελο",
                                               "«%@» esiste già nella stessa cartella",
                                               "„%@“ ist im selben Ordner bereits vorhanden",
                                               "«%@» уже існує в цій папці"],
    "“%@” starts with a dot and would become hidden": [
        "Το «%@» αρχίζει με τελεία και θα γινόταν κρυφό", "«%@» inizia con un punto e diventerebbe nascosto",
        "„%@“ beginnt mit einem Punkt und wäre dann unsichtbar", "«%@» починається з крапки й стане прихованим"],
    "No longer there: moved or deleted since the search": [
        "Δεν υπάρχει πια: μετακινήθηκε ή σβήστηκε μετά την αναζήτηση",
        "Non c’è più: spostato o eliminato dopo la ricerca",
        "Nicht mehr vorhanden: seit der Suche verschoben oder gelöscht",
        "Більше не існує: переміщено або видалено після пошуку"],
    "Something else is now in its place. Search again": [
        "Στη θέση του υπάρχει πλέον κάτι άλλο. Κάνε ξανά αναζήτηση",
        "Al suo posto ora c’è altro. Cerca di nuovo",
        "An seiner Stelle liegt jetzt etwas anderes. Suche erneut",
        "На його місці тепер щось інше. Виконайте пошук ще раз"],
    "Finds files by name, then renames them or moves them to the Trash.": [
        "Βρίσκει αρχεία με βάση το όνομα και τα μετονομάζει ή τα στέλνει στον Κάδο.",
        "Trova i file per nome, poi li rinomina o li sposta nel Cestino.",
        "Findet Dateien nach Namen und benennt sie um oder legt sie in den Papierkorb.",
        "Знаходить файли за назвою, а потім перейменовує їх або переміщує в Смітник."],
    "Version %@ (%@)": ["Έκδοση %@ (%@)", "Versione %@ (%@)", "Version %@ (%@)", "Версія %@ (%@)"],
    "Continue": ["Συνέχεια", "Continua", "Weiter", "Продовжити"],
    "About Proteus": ["Σχετικά με το Proteus", "Informazioni su Proteus", "Über Proteus", "Про Proteus"],
    "Created by Charis Tsevis, with the help of Claude Code.": [
        "Δημιουργήθηκε από τον Χάρη Τσεβή, με τη βοήθεια του Claude Code.",
        "Creato da Charis Tsevis, con l’aiuto di Claude Code.",
        "Erstellt von Charis Tsevis, mit Hilfe von Claude Code.",
        "Створено Харісом Тсевісом за допомогою Claude Code."],
    "about.body": [
        "Διάλεξε έναν φάκελο και γράψε ένα κομμάτι ονόματος. Το Proteus βρίσκει κάθε αρχείο και φάκελο "
        "από κάτω του που το περιέχει, σου δείχνει πώς θα λέγεται το καθένα πριν αλλάξει οτιδήποτε, και "
        "μετά το μετονομάζει ή το στέλνει στον Κάδο. Με το Regex μπορείς να σβήσεις αριθμούς, κενά ή "
        "ολόκληρες λέξεις.\n\nΤίποτα δεν φεύγει από αυτόν τον Mac. Τίποτα δεν σβήνεται οριστικά: ό,τι "
        "πετάς πάει στον Κάδο, και ένα όνομα που υπάρχει ήδη δεν αντικαθίσταται ποτέ.",
        "Scegli una cartella e scrivi parte di un nome. Proteus trova ogni file e cartella al suo interno "
        "il cui nome lo contiene, ti mostra come si chiamerà ciascuno prima di cambiare qualsiasi cosa, e "
        "poi lo rinomina o lo sposta nel Cestino. Con Regex puoi eliminare numeri, spazi o parole intere."
        "\n\nNulla lascia questo Mac. Nulla viene eliminato definitivamente: ciò che butti va nel Cestino, "
        "e un nome già esistente non viene mai sostituito.",
        "Wähle einen Ordner und gib einen Teil eines Namens ein. Proteus findet darin jede Datei und jeden "
        "Ordner, deren Name ihn enthält, zeigt dir vor jeder Änderung, wie sie heißen werden, und benennt "
        "sie dann um oder legt sie in den Papierkorb. Mit Regex kannst du Zahlen, Leerzeichen oder ganze "
        "Wörter entfernen.\n\nNichts verlässt diesen Mac. Nichts wird endgültig gelöscht: Was du wegwirfst, "
        "landet im Papierkorb, und ein bereits vorhandener Name wird nie ersetzt.",
        "Виберіть папку й введіть частину назви. Proteus знаходить у ній кожен файл і папку, назва яких її "
        "містить, показує, як кожен із них називатиметься, ще до будь-яких змін, а потім перейменовує його "
        "або переміщує в Смітник. За допомогою Regex можна прибрати цифри, пробіли чи цілі слова.\n\n"
        "Ніщо не залишає цей Mac. Ніщо не видаляється назавжди: усе викинуте потрапляє до Смітника, а "
        "наявна назва ніколи не замінюється."],
}


T.update(T_V11)


def escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main() -> None:
    root = pathlib.Path(__file__).resolve().parent.parent / "Resources" / "Localization"
    for index, lang in enumerate(LANGS):
        lines = [f'"{escape(key)}" = "{escape(values[index])}";' for key, values in T.items()]
        folder = root / f"{lang}.lproj"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "Localizable.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")
    english = root / "en.lproj"
    english.mkdir(parents=True, exist_ok=True)
    (english / "Localizable.strings").write_text("/* English is the source text in the code. */\n",
                                                 encoding="utf-8")


if __name__ == "__main__":
    main()
