import type { FastifyInstance } from 'fastify';
import {
  practiceCatalogActivityIds, practiceCatalogById, practiceCatalogContentVersion,
  practiceCatalogFloors, practiceCatalogPayloadVersion, practiceCatalogSchemaVersion,
} from '@trimmy/domain';

const catalog = Object.freeze({
  schemaVersion: practiceCatalogSchemaVersion,
  contentVersion: practiceCatalogContentVersion,
  currentPayloadVersion: practiceCatalogPayloadVersion,
  supportedPayloadVersions: Object.freeze([3, 4, 5, 6]),
  floors: practiceCatalogFloors,
  activities: Object.freeze(practiceCatalogActivityIds.map(id => practiceCatalogById[id])),
});

/** Public authored metadata only; no account state or provider calls. */
export function registerPracticeCatalogRoute(app: FastifyInstance): void {
  app.get('/v1/practice/catalog', {
    schema: {querystring: {type: 'object', additionalProperties: false, properties: {}}},
  }, async () => catalog);
}
