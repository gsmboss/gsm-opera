const translations = {
  ru: {
    "nav-home": "Главная",
    "nav-services": "Услуги",
    "nav-gallery": "Галерея",
    "nav-contact": "Контакты",
    "home-title": "Профессиональный сервис разблокировки телефонов",
    "home-text": "Opera GSM Fix — это надёжная команда, которая помогает разблокировать FRP, MDM, PIN и другие ограничения на телефонах Xiaomi, Infinix, Tecno, Itel, Honor и Google Pixel.",
    "services-title": "Наши услуги",
    "srv-xiaomi": "Удаления FRP, Mi Account, CPID, UNLOCK BOOTLOADER, Прошивка.",
    "srv-infinix": "Официальное открытие MDM, Обход MDM, Удаления FRP, Прошивка.",
    "srv-samsung" : "Удаления KG, Удаления FRP, Удаления MDM, Прошивка.",
    "srv-honor": "Удаления FRP, Удаления ID.",
    "srv-pixel": "Удаления FRP.",
    "srv-Activation": "Активация всех инструментов.",
    "srv-rent": "Аренда всего инструмента.",
    "srv-credit": "Все кредиты на инструменты.",
    "gallery-title": "Наши работы",
    "gallery-text": "Вот несколько примеров успешной разблокировки и ремонта:",
    "contact-title": "Контакты",
    "contact-text": "Свяжитесь с нами в Telegram:"
  },
  uz: {
    "nav-home": "Bosh sahifa",
    "nav-services": "Xizmatlar",
    "nav-gallery": "Galereya",
    "nav-contact": "Aloqa",
    "home-title": "Telefonlarni professional ochish xizmati",
    "home-text": "Opera GSM Fix — bu Xiaomi, Infinix, Tecno, Itel, Honor va Google Pixel telefonlaridagi FRP, MDM, PIN va boshqa cheklovlarni olib tashlashga yordam beradigan ishonchli jamoa.",
    "services-title": "Bizning xizmatlarimiz",
    "srv-xiaomi": "FRP qayta o'rnatish, Mi hisob qaydnomasi, CPID, BOOTLOADERni qulfdan chiqarish, Flash.",
    "srv-infinix": "Rasmiy MDM qulfini ochish, MDMni chetlab o'tish, FRP, Flashni olib tashlash.",
    "srv-samsung" : "KGni olib tashlang, FRPni qulfdan chiqaring, MDM, Flashni olib tashlang.",
    "srv-honor": "FRP qulfini tiklash, IDni olib tashlash.",
    "srv-pixel": "FRP qulfini qayta tiklash.",
    "srv-Activation": "Barcha tullar faollashtirish.",
    "srv-rent": "Barcha tullar arendaga.",
    "srv-credit": "Barcha tullar uchun credit",
    "gallery-title": "Bizning ishlarimiz",
    "gallery-text": "Quyida muvaffaqiyatli ochilgan va tuzatilgan telefonlardan misollar:",
    "contact-title": "Aloqa",
    "contact-text": "Biz bilan Telegramda bog‘laning:"
  },
  en: {
    "nav-home": "Home",
    "nav-services": "Services",
    "nav-gallery": "Gallery",
    "nav-contact": "Contact",
    "home-title": "Professional phone unlock service",
    "home-text": "Opera GSM Fix is a reliable team that helps remove FRP, MDM, PIN and other locks on Xiaomi, Infinix, Tecno, Itel, Honor and Google Pixel phones.",
    "services-title": "Our Services",
    "srv-xiaomi": "FRP Reset, Mi Account, CPID, UNLOCK BOOTLOADER, Flash.",
    "srv-infinix": "Oficcial unlock MDM, Bypass MDM, Remove FRP, Flash.",
    "srv-samsung" : "Remove KG, Unlock FRP, Remove MDM, Flash.",
    "srv-honor": "Reset FRP unlock, Remove ID.",
    "srv-pixel": "Reset FRP unlock.",
    "srv-Activation": "All tool activation.",
    "srv-rent": "All tool rent.",
    "srv-credit": "All tool credits.",
    "gallery-title": "Our Works",
    "gallery-text": "Here are a few examples of successful unlocks and repairs:",
    "contact-title": "Contact",
    "contact-text": "Contact us on Telegram:"
  }
};

function setLanguage(lang) {
  const elements = document.querySelectorAll("[data-lang]");
  elements.forEach(el => {
    const key = el.getAttribute("data-lang");
    el.textContent = translations[lang][key];
  });
  localStorage.setItem("lang", lang);
}

document.addEventListener("DOMContentLoaded", () => {
  const savedLang = localStorage.getItem("lang") || "ru";
  setLanguage(savedLang);

  // Тёмная тема
  const themeToggle = document.getElementById("theme-toggle");
  themeToggle.addEventListener("click", () => {
    document.body.classList.toggle("dark");
    themeToggle.textContent = document.body.classList.contains("dark") ? "☀️" : "🌙";
    localStorage.setItem("theme", document.body.classList.contains("dark") ? "dark" : "light");
  });

  // Сохранённая тема
  if (localStorage.getItem("theme") === "dark") {
    document.body.classList.add("dark");
    themeToggle.textContent = "☀️";
  }

  // Анимация появления
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (entry.isIntersecting) entry.target.classList.add("visible");
    });
  }, { threshold: 0.2 });

  document.querySelectorAll(".fade-in").forEach(el => observer.observe(el));
});

let currentSlide = 0;
const slides = document.querySelectorAll('.carousel img');
const totalSlides = slides.length;
const carousel = document.querySelector('.carousel');

function showSlide(index) {
    carousel.style.transform = `translateX(-${index * 100}%)`;
}

function nextSlide() {
    currentSlide = (currentSlide + 1) % totalSlides;
    showSlide(currentSlide);
}

// авто-перелистывание каждые 3 секунды
setInterval(nextSlide, 3000);

// свайп для мобильных
let startX = 0;
carousel.addEventListener('touchstart', e => startX = e.touches[0].clientX);
carousel.addEventListener('touchend', e => {
    const endX = e.changedTouches[0].clientX;
    if (startX - endX > 50) nextSlide(); // свайп влево
    if (endX - startX > 50) {
        currentSlide = (currentSlide - 1 + totalSlides) % totalSlides;
        showSlide(currentSlide);
    }
});

const fadeElements = document.querySelectorAll('.fade-in');
window.addEventListener('scroll', () => {
    fadeElements.forEach(el => {
        const rect = el.getBoundingClientRect();
        if (rect.top < window.innerHeight - 100) {
            el.classList.add('visible');
        }
    });
});

