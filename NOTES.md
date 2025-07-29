- [ ] also implement the option to apply buffered updates to resources (akin to the buffered component query/updates).

  - in fact, maybe buffered updates should be the only way to update anything, both resource and component wise?

- [x] when adding a component to an entity, assert that the component is unique within the context of the said entity. in other words, an entity shouldn't be related to more than one of the same type of component.

- [x] rework resource system to be less clunky to work with. we should consider how to efficiently and elegantly store and query both singleton values and collections.
