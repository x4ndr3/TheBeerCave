import './style.css'

// Smooth scrolling for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
  anchor.addEventListener('click', function (e) {
    e.preventDefault();
    const targetId = this.getAttribute('href');
    const targetSection = document.querySelector(targetId);
    if (targetSection) {
      targetSection.scrollIntoView({
        behavior: 'smooth'
      });
    }
  });
});

// Contact Form
const form = document.getElementById('contact-form');
if (form) {
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const status = document.getElementById('form-status');
    const btn = form.querySelector('button');

    // Simple validation
    const formData = new FormData(form);
    const data = Object.fromEntries(formData.entries());

    // Disable button
    btn.disabled = true;
    btn.textContent = 'Sending...';
    status.textContent = '';

    // For now we just simulate success or point to the future API
    // In production, this will point to the API Gateway URL
    const apiUrl = import.meta.env.VITE_API_URL + '/contact';

    try {
      const response = await fetch(apiUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
      });

      if (!response.ok) throw new Error('Failed to send message');

      status.textContent = 'Message received! Game on!';
      status.style.color = 'var(--color-accent)';
      form.reset();

    } catch (err) {
      status.textContent = 'Error sending message. Please try again.';
      status.style.color = 'red';
      console.error(err);
    } finally {
      btn.disabled = false;
      btn.textContent = 'Send Message';
    }
  });
}
