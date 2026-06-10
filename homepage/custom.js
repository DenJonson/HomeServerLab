function replaceDynamicHosts() {
    // Получаем текущий хост из адресной строки (например, localhost или 192.168.0.30)
    const currentHost = window.location.hostname;

    // Ищем все ссылки, содержащие специальный маркер-плейсхолдер
    document.querySelectorAll('a').forEach(link => {
        if (link.href && link.href.includes('dynamic-host')) {
            link.href = link.href.replace('dynamic-host', currentHost);
        }
    });
}

// Отслеживаем динамическое появление элементов в DOM (так как это React/Next.js)
const observer = new MutationObserver(replaceDynamicHosts);
observer.observe(document.body, { childList: true, subtree: true });
