(() => {
  document.documentElement.classList.add('page-enhanced');

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const desktopMotion = window.matchMedia('(min-width: 56.0625rem)');

  const canAnimate = () => !reduceMotion.matches;

  // Keep the navigation legible after it leaves the dark hero without changing
  // the initial poster composition.
  const header = document.querySelector('.site-header');
  const parallaxItems = [...document.querySelectorAll('[data-parallax]')];
  let frameRequested = false;

  function updateViewportEffects() {
    frameRequested = false;
    header?.classList.toggle('is-scrolled', window.scrollY > 24);

    const allowDepth = canAnimate() && desktopMotion.matches;
    const viewportCentre = window.innerHeight / 2;
    parallaxItems.forEach((item) => {
      if (!allowDepth) {
        item.style.removeProperty('--parallax-y');
        return;
      }
      const rect = item.getBoundingClientRect();
      const distance = (rect.top + rect.height / 2 - viewportCentre) / window.innerHeight;
      const depth = Number(item.dataset.parallax) || 0;
      const offset = Math.max(-Math.abs(depth), Math.min(Math.abs(depth), distance * -depth));
      item.style.setProperty('--parallax-y', `${offset.toFixed(2)}px`);
    });
  }

  function requestViewportEffects() {
    if (frameRequested) return;
    frameRequested = true;
    requestAnimationFrame(updateViewportEffects);
  }

  window.addEventListener('scroll', requestViewportEffects, { passive: true });
  window.addEventListener('resize', requestViewportEffects, { passive: true });
  reduceMotion.addEventListener?.('change', requestViewportEffects);
  desktopMotion.addEventListener?.('change', requestViewportEffects);
  updateViewportEffects();

  /* ─────────────────────────────────────────────────────────
   * EXAMPLE RULE STORYBOARD
   *
   * Static product facts remain readable throughout.
   *
   *    0ms   Watching — chart redraws from its starting price
   * 1100ms   Condition met — the WHEN row and threshold respond
   * 2500ms   Acted — the THEN row and compact result stay visible
   * ───────────────────────────────────────────────────────── */
  const RULE_DEMO_TIMING = {
    autoplayDelay: 650,
    condition: 1100,
    action: 2500
  };
  const RULE_DEMO_COPY = {
    watching: {
      status: 'Watching',
      title: 'Watching the price',
      copy: 'Waiting for the condition you set.',
      icon: '•'
    },
    met: {
      status: 'Condition met',
      title: 'Condition met',
      copy: '1 XRP reached 150 FLR.',
      icon: '!'
    },
    acted: {
      status: 'Exchange complete',
      title: '0.01 XRP exchanged',
      copy: '0.11 XRP remains available.',
      icon: '✓'
    }
  };

  const heroRule = document.querySelector('[data-motion="hero-rule"]');
  const ruleStatus = heroRule?.querySelector('[data-rule-status]');
  const ruleReplay = heroRule?.querySelector('[data-rule-replay]');
  const ruleReplayIcon = heroRule?.querySelector('[data-rule-replay-icon]');
  const ruleReplayLabel = heroRule?.querySelector('[data-rule-replay-label]');
  const ruleReceiptTitle = heroRule?.querySelector('[data-rule-receipt-title]');
  const ruleReceiptCopy = heroRule?.querySelector('[data-rule-receipt-copy]');
  const ruleReceiptIcon = heroRule?.querySelector('.rule-demo__receipt-icon');
  let ruleDemoTimers = [];
  let ruleDemoRun = 0;
  let ruleDemoUserStarted = false;
  let heroObserver;

  function clearRuleDemo() {
    ruleDemoRun += 1;
    ruleDemoTimers.forEach(clearTimeout);
    ruleDemoTimers = [];
  }

  function setRuleDemoState(state) {
    if (!heroRule || !RULE_DEMO_COPY[state]) return;
    const copy = RULE_DEMO_COPY[state];
    heroRule.dataset.demoState = state;
    if (ruleStatus) ruleStatus.textContent = copy.status;
    if (ruleReceiptTitle) ruleReceiptTitle.textContent = copy.title;
    if (ruleReceiptCopy) ruleReceiptCopy.textContent = copy.copy;
    if (ruleReceiptIcon) ruleReceiptIcon.textContent = copy.icon;
  }

  function runRuleDemo() {
    if (!heroRule) return;
    clearRuleDemo();

    if (!canAnimate()) {
      heroRule.classList.remove('is-demo-running');
      setRuleDemoState('acted');
      if (ruleReplayIcon) ruleReplayIcon.textContent = '↻';
      if (ruleReplayLabel) ruleReplayLabel.textContent = 'Replay example';
      return;
    }

    const run = ruleDemoRun;
    setRuleDemoState('watching');
    if (ruleReplayIcon) ruleReplayIcon.textContent = '↻';
    if (ruleReplayLabel) ruleReplayLabel.textContent = 'Restart example';
    heroRule.classList.remove('is-demo-running');
    void heroRule.offsetWidth;
    heroRule.classList.add('is-demo-running');

    ruleDemoTimers.push(setTimeout(() => {
      if (run !== ruleDemoRun) return;
      setRuleDemoState('met');
    }, RULE_DEMO_TIMING.condition));

    ruleDemoTimers.push(setTimeout(() => {
      if (run !== ruleDemoRun) return;
      setRuleDemoState('acted');
      heroRule.classList.remove('is-demo-running');
      if (ruleReplayLabel) ruleReplayLabel.textContent = 'Replay example';
    }, RULE_DEMO_TIMING.action));
  }

  ruleReplay?.addEventListener('click', () => {
    ruleDemoUserStarted = true;
    heroObserver?.disconnect();
    runRuleDemo();
  });

  if (heroRule && canAnimate() && 'IntersectionObserver' in window) {
    heroObserver = new IntersectionObserver((entries, observer) => {
      if (!entries[0]?.isIntersecting || ruleDemoUserStarted) return;
      observer.unobserve(heroRule);
      ruleDemoTimers.push(setTimeout(() => {
        if (!ruleDemoUserStarted) runRuleDemo();
      }, RULE_DEMO_TIMING.autoplayDelay));
    }, { threshold: 0.55 });
    heroObserver.observe(heroRule);
  }

  reduceMotion.addEventListener?.('change', () => {
    if (!reduceMotion.matches || !heroRule) return;
    clearRuleDemo();
    heroRule.classList.remove('is-demo-running');
    setRuleDemoState('acted');
    if (ruleReplayIcon) ruleReplayIcon.textContent = '↻';
    if (ruleReplayLabel) ruleReplayLabel.textContent = 'Replay example';
  });

  // Accessible tabs with a short directional transition between product
  // states. The transition never delays or blocks the state change.
  const storyTabs = [...document.querySelectorAll('[data-story-tab]')];
  const storyPanels = [...document.querySelectorAll('[data-story-panel]')];

  function selectStoryTab(tab, direction = 1) {
    if (tab.getAttribute('aria-selected') === 'true') return;
    const target = tab.dataset.storyTab;
    const selectedPanel = storyPanels.find((panel) => panel.dataset.storyPanel === target);

    storyTabs.forEach((item) => {
      const selected = item === tab;
      item.classList.toggle('is-active', selected);
      item.setAttribute('aria-selected', String(selected));
      item.tabIndex = selected ? 0 : -1;
    });

    storyPanels.forEach((panel) => {
      const selected = panel === selectedPanel;
      panel.classList.toggle('is-active', selected);
      panel.hidden = !selected;
    });

    if (!selectedPanel || !canAnimate() || typeof selectedPanel.animate !== 'function') return;
    selectedPanel.getAnimations().forEach((animation) => animation.cancel());
    selectedPanel.animate([
      { opacity: 0, transform: `translate3d(${direction * 8}px, 0, 0)` },
      { opacity: 1, transform: 'translate3d(0, 0, 0)' }
    ], { duration: 220, easing: 'cubic-bezier(.23,1,.32,1)' });
  }

  storyTabs.forEach((tab, index) => {
    tab.addEventListener('click', () => {
      const currentIndex = storyTabs.findIndex((item) => item.getAttribute('aria-selected') === 'true');
      selectStoryTab(tab, index >= currentIndex ? 1 : -1);
    });
    tab.addEventListener('keydown', (event) => {
      if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key)) return;
      event.preventDefault();

      let nextIndex;
      if (event.key === 'Home') nextIndex = 0;
      else if (event.key === 'End') nextIndex = storyTabs.length - 1;
      else {
        const direction = event.key === 'ArrowRight' || event.key === 'ArrowDown' ? 1 : -1;
        nextIndex = (index + direction + storyTabs.length) % storyTabs.length;
      }

      const next = storyTabs[nextIndex];
      selectStoryTab(next, nextIndex >= index ? 1 : -1);
      next.focus();
    });
  });

  // Mobile rule-card carousel controls. Scroll work is kept to one animation
  // frame so the counter remains cheap during touch momentum.
  const carousel = document.querySelector('[data-capability-carousel]');
  const capabilityCards = carousel ? [...carousel.querySelectorAll('.capability')] : [];
  const capabilityCurrent = document.querySelector('[data-capability-current]');
  let carouselFrame = false;
  let lastCapability = 0;

  function activeCapability() {
    if (!carousel || !capabilityCards.length) return 0;
    const centre = carousel.scrollLeft + carousel.clientWidth / 2;
    return capabilityCards.reduce((closest, card, index) => {
      const cardCentre = card.offsetLeft + card.offsetWidth / 2;
      const distance = Math.abs(cardCentre - centre);
      return distance < closest.distance ? { index, distance } : closest;
    }, { index: 0, distance: Number.POSITIVE_INFINITY }).index;
  }

  function showCapability(index) {
    capabilityCards[(index + capabilityCards.length) % capabilityCards.length]?.scrollIntoView({
      behavior: canAnimate() ? 'smooth' : 'auto',
      block: 'nearest',
      inline: 'start'
    });
  }

  document.querySelector('[data-capability-prev]')?.addEventListener('click', () => showCapability(activeCapability() - 1));
  document.querySelector('[data-capability-next]')?.addEventListener('click', () => showCapability(activeCapability() + 1));
  carousel?.addEventListener('scroll', () => {
    if (carouselFrame) return;
    carouselFrame = true;
    requestAnimationFrame(() => {
      carouselFrame = false;
      const active = activeCapability();
      if (!capabilityCurrent || active === lastCapability) return;
      lastCapability = active;
      capabilityCurrent.textContent = String(active + 1);
      if (canAnimate() && typeof capabilityCurrent.animate === 'function') {
        capabilityCurrent.animate([
          { opacity: .3, transform: 'translateY(3px)' },
          { opacity: 1, transform: 'translateY(0)' }
        ], { duration: 140, easing: 'ease-out' });
      }
    });
  }, { passive: true });

  // Keep the preview and the actual setup destination in lockstep. These are
  // the same four presets exposed by the arming page.
  const builderChoices = [...document.querySelectorAll('[data-builder-preset]')];
  const builderWindow = document.querySelector('.builder-window');
  const builderContent = document.querySelector('[data-builder-content]');
  const builderCopy = {
    below: {
      type: 'Price rule',
      title: 'Sell if XRP falls',
      when: '1 XRP reaches 150 FLR or less',
      then: 'Exchange 0.01 XRP for FLR',
      amount: '0.01 XRP',
      runs: '12 times',
      ends: 'In 7 days',
      noteTitle: 'Review before approval',
      note: 'You’ll review the full rule before anything moves.'
    },
    swap: {
      type: 'Scheduled exchange',
      title: 'Exchange every hour',
      when: 'The rule starts, then every hour',
      then: 'Exchange 0.01 XRP for FLR',
      amount: '0.01 XRP',
      runs: '12 times',
      ends: 'In 7 days',
      noteTitle: 'Review before approval',
      note: 'You’ll confirm the cadence and limits before approval.'
    },
    vault: {
      type: 'Scheduled deposit',
      title: 'Deposit every hour',
      when: 'The rule starts, then every hour',
      then: 'Deposit 1 XRP into the XRP yield vault',
      amount: '1 XRP',
      runs: '12 times',
      ends: 'In 7 days',
      noteTitle: 'Review before approval',
      note: 'You’ll confirm the cadence and limits before approval.'
    },
    private: {
      type: 'Private price · advanced',
      title: 'Sell at a private price',
      when: 'XRP falls to the private price I set',
      then: 'Exchange 0.01 XRP for FLR',
      amount: '0.01 XRP',
      runs: '12 times',
      ends: 'In 7 days',
      noteTitle: 'Advanced setup',
      note: 'After the rule exists, you add the private price separately.'
    }
  };

  const builderFields = {
    type: document.querySelector('[data-builder-type]'),
    title: document.querySelector('[data-builder-title]'),
    when: document.querySelector('[data-builder-when]'),
    then: document.querySelector('[data-builder-then]'),
    amount: document.querySelector('[data-builder-amount]'),
    runs: document.querySelector('[data-builder-runs]'),
    ends: document.querySelector('[data-builder-ends]'),
    noteTitle: document.querySelector('[data-builder-note-title]'),
    note: document.querySelector('[data-builder-note]')
  };
  const builderAnnouncer = document.querySelector('[data-builder-announcer]');
  const builderOrder = Object.keys(builderCopy);
  let currentBuilderPreset = 'below';

  function updateBuilderPreview(animate = true) {
    if (!builderChoices.length || !builderWindow) return;
    const selected = builderChoices.find((choice) => choice.checked);
    const preset = selected?.value in builderCopy ? selected.value : 'below';
    const copy = builderCopy[preset];
    const previousIndex = builderOrder.indexOf(currentBuilderPreset);
    const nextIndex = builderOrder.indexOf(preset);
    const direction = nextIndex >= previousIndex ? 1 : -1;
    currentBuilderPreset = preset;
    builderWindow.dataset.preset = preset;

    Object.entries(builderFields).forEach(([key, node]) => {
      if (!node || node.textContent === copy[key]) return;
      node.textContent = copy[key];
    });

    if (animate && canAnimate()) {
      builderContent?.getAnimations().forEach((animation) => animation.cancel());
      builderWindow.getAnimations().forEach((animation) => animation.cancel());

      builderContent?.animate([
        { opacity: .2, transform: `translate3d(${direction * 10}px, 0, 0)` },
        { opacity: 1, transform: 'translate3d(0, 0, 0)' }
      ], { duration: 240, easing: 'cubic-bezier(.23,1,.32,1)' });

      const mobile = window.matchMedia('(max-width:47.9375rem)').matches;
      builderWindow.animate([
        { transform: `translate3d(${direction * 9}px, 4px, 0) rotate(${mobile ? 0 : .35}deg) scale(.985)` },
        { transform: `translate3d(0, 0, 0) rotate(${mobile ? 0 : 1}deg) scale(1)` }
      ], { duration: 300, easing: 'cubic-bezier(.23,1,.32,1)' });
    }

    if (animate && builderAnnouncer) builderAnnouncer.textContent = `Preview updated: ${copy.title}.`;
  }

  builderChoices.forEach((choice) => choice.addEventListener('change', () => updateBuilderPreview(true)));
  updateBuilderPreview(false);
})();
