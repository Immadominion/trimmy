import {useMemo} from 'react';
import {ProductApp as ProductWorkspaceApp} from './product/ProductApp';
import {productApiBase} from './product/config';
import {createWebUsage} from './product/usage';
import './product/product.css';
import './product/market.css';
import './product/desk.css';
import './product/profile.css';
import './product/dashboard.css';
import './product/company-coin.css';
import './product/career-world.css';
import './product/career-journey.css';
import './product/workday-screen.css';
import './product/money/money.css';
import './product/journey.css';
import './product/settings.css';
import './product/market-social.css';
import './product/entry-split.css';

/** The production app: the same product, with first-party usage events on. */
function ProductApp() {
  const usage = useMemo(() => createWebUsage(productApiBase()), []);
  return <ProductWorkspaceApp usage={usage}/>;
}

export {ProductApp};
