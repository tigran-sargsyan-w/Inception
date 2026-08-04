const themeToggle = document.querySelector("#theme-toggle");
const currentYear = document.querySelector("#current-year");

currentYear.textContent = new Date().getFullYear();

themeToggle.addEventListener("click", () => {
	document.body.classList.toggle("dark");
});